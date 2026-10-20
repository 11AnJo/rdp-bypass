@echo off
setlocal enabledelayedexpansion
title RdpBypass - Uninstaller

:: ============================================================
::  Require administrator privileges
:: ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run as administrator.
    echo         Right-click -^> Run as administrator
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  Configuration
:: ============================================================
set "INSTALL_DIR=C:\RdpBypass"
set "KEY_WOW=HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
set "KEY_NATIVE=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"

set "OS64=0"
if defined ProgramFiles(x86) set "OS64=1"

echo ============================================================
echo   RdpBypass - Uninstaller (x86 + x64)
echo ============================================================
echo.

:: ============================================================
::  Uninstall 32-bit
:: ============================================================
if "%OS64%"=="1" (
    call :uninstall_arch "RdpBypass32.dll" "%KEY_WOW%" "backup32.reg.txt" "x86"
) else (
    call :uninstall_arch "RdpBypass32.dll" "%KEY_NATIVE%" "backup32.reg.txt" "x86"
)

:: ============================================================
::  Uninstall 64-bit (64-bit OS only)
:: ============================================================
if "%OS64%"=="1" (
    call :uninstall_arch "RdpBypass64.dll" "%KEY_NATIVE%" "backup64.reg.txt" "x64"
)

:: ============================================================
::  Remove install directory (if now empty)
:: ============================================================
if exist "%INSTALL_DIR%" (
    rd /q "%INSTALL_DIR%" 2>nul
    if not exist "%INSTALL_DIR%" (
        echo [Uninstall] Removed directory: %INSTALL_DIR%
    ) else (
        echo [WARN] Directory not empty or in use ^(DLL may still be loaded^); remove after reboot: %INSTALL_DIR%
    )
)

echo.
echo   Uninstall complete.
echo.
pause
exit /b 0

:: ============================================================
::  Subroutine: uninstall_arch  DLLNAME  KEY  BACKUPNAME  LABEL
:: ============================================================
:uninstall_arch
setlocal enabledelayedexpansion
set "U_DLLNAME=%~1"
set "U_KEY=%~2"
set "U_DLLPATH=%INSTALL_DIR%\%~1"
set "U_BACKUP=%INSTALL_DIR%\%~3"
set "U_LABEL=%~4"

echo ------------------------------------------------------------
echo   [%U_LABEL%] %U_KEY%
echo ------------------------------------------------------------

:: --- Read backup ---
set "BAK_APPINIT="
set "BAK_LOAD="
set "BAK_SIGNED="
set "HAS_BACKUP=0"
if exist "%U_BACKUP%" (
    set "HAS_BACKUP=1"
    for /f "tokens=1,* delims==" %%a in ('type "%U_BACKUP%" ^| findstr /v "^#"') do (
        if "%%a"=="AppInit_DLLs" set "BAK_APPINIT=%%b"
        if "%%a"=="LoadAppInit_DLLs" set "BAK_LOAD=%%b"
        if "%%a"=="RequireSignedAppInit_DLLs" set "BAK_SIGNED=%%b"
    )
    echo [Info] Loaded pre-install backup
)

:: --- Remove our DLL from AppInit_DLLs (or restore from backup) ---
set "CUR_APPINIT="
for /f "tokens=2*" %%a in ('reg query "%U_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "CUR_APPINIT=%%b"
echo "!CUR_APPINIT!" | findstr /i /c:"%U_DLLPATH%" >nul 2>&1
if !errorlevel! equ 0 (
    if "!HAS_BACKUP!"=="1" (
        reg add "%U_KEY%" /v AppInit_DLLs /t REG_SZ /d "!BAK_APPINIT!" /f >nul
    ) else (
        set "NEW_APPINIT=!CUR_APPINIT!"
        set "NEW_APPINIT=!NEW_APPINIT:%U_DLLPATH% =!"
        set "NEW_APPINIT=!NEW_APPINIT: %U_DLLPATH%=!"
        set "NEW_APPINIT=!NEW_APPINIT:%U_DLLPATH%=!"
        for /f "tokens=*" %%x in ("!NEW_APPINIT!") do set "NEW_APPINIT=%%x"
        reg add "%U_KEY%" /v AppInit_DLLs /t REG_SZ /d "!NEW_APPINIT!" /f >nul
    )
    echo [Uninstall] Removed DLL path from AppInit_DLLs
) else (
    echo [Skip] AppInit_DLLs does not contain this DLL
)

:: --- Restore LoadAppInit_DLLs ---
if "!HAS_BACKUP!"=="1" (
    if defined BAK_LOAD (
        set /a "RESTORE_LOAD=!BAK_LOAD!" 2>nul
        reg add "%U_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d !RESTORE_LOAD! /f >nul
        echo [Uninstall] LoadAppInit_DLLs restored from backup
    )
) else (
    set "REMAINING="
    for /f "tokens=2*" %%a in ('reg query "%U_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "REMAINING=%%b"
    if "!REMAINING!"=="" (
        reg add "%U_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 0 /f >nul
        echo [Uninstall] AppInit_DLLs empty; set LoadAppInit_DLLs = 0
    ) else (
        echo [Skip] AppInit_DLLs still has other entries; keeping LoadAppInit_DLLs
    )
)

:: --- Restore RequireSignedAppInit_DLLs ---
if "!HAS_BACKUP!"=="1" (
    if defined BAK_SIGNED (
        set /a "RESTORE_SIGNED=!BAK_SIGNED!" 2>nul
        reg add "%U_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d !RESTORE_SIGNED! /f >nul
        echo [Uninstall] RequireSignedAppInit_DLLs restored from backup
    )
)

:: --- Delete DLL and backup file ---
if exist "%U_DLLPATH%" (
    del /f /q "%U_DLLPATH%" 2>nul
    if exist "%U_DLLPATH%" (
        echo [WARN] DLL in use; remove after reboot: %U_DLLPATH%
    ) else (
        echo [Uninstall] Deleted DLL: %U_DLLPATH%
    )
)
if exist "%U_BACKUP%" del /f /q "%U_BACKUP%" 2>nul

endlocal
exit /b 0
