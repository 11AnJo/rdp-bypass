@echo off
setlocal enabledelayedexpansion
title RdpBypass - Uninstaller

:: ============================================================
::  Require administrator privileges
:: ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo This uninstaller needs administrator rights because it writes to HKEY_LOCAL_MACHINE.
    echo Please close this window and run Uninstall.bat again via right-click -^> Run as administrator.
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
echo   RdpBypass - Uninstaller
echo ============================================================
echo.
echo   This restores the registry values saved at install time and
echo   removes the DLLs from %INSTALL_DIR%.
echo.

:: ============================================================
::  Uninstall 32-bit
:: ============================================================
if "%OS64%"=="1" (
    call :uninstall_arch "RdpBypass32.dll" "%KEY_WOW%" "backup32.reg.txt" "32-bit apps"
) else (
    call :uninstall_arch "RdpBypass32.dll" "%KEY_NATIVE%" "backup32.reg.txt" "32-bit apps"
)

:: ============================================================
::  Uninstall 64-bit (64-bit OS only)
:: ============================================================
if "%OS64%"=="1" (
    call :uninstall_arch "RdpBypass64.dll" "%KEY_NATIVE%" "backup64.reg.txt" "64-bit apps"
)

:: ============================================================
::  Remove install directory (if now empty)
:: ============================================================
if exist "%INSTALL_DIR%" (
    rd /q "%INSTALL_DIR%" 2>nul
    if not exist "%INSTALL_DIR%" (
        echo Removed folder: %INSTALL_DIR%
    ) else (
        echo Could not remove %INSTALL_DIR% yet ^(a DLL may still be loaded^); delete it after a reboot.
    )
)

echo.
echo   Done. RdpBypass has been removed and the registry restored.
echo   A reboot clears the DLL out of any processes still using it.
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

echo.
echo --- Removing the hook for %U_LABEL% (%U_DLLNAME%) ---

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
    echo   Loaded the pre-install backup
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
    echo   Removed the DLL from AppInit_DLLs
) else (
    echo   AppInit_DLLs did not list this DLL
)

:: --- Restore LoadAppInit_DLLs ---
if "!HAS_BACKUP!"=="1" (
    if defined BAK_LOAD (
        set /a "RESTORE_LOAD=!BAK_LOAD!" 2>nul
        reg add "%U_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d !RESTORE_LOAD! /f >nul
        echo   Restored LoadAppInit_DLLs from backup
    )
) else (
    set "REMAINING="
    for /f "tokens=2*" %%a in ('reg query "%U_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "REMAINING=%%b"
    if "!REMAINING!"=="" (
        reg add "%U_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 0 /f >nul
        echo   AppInit_DLLs is now empty; disabled AppInit loading
    ) else (
        echo   AppInit_DLLs still has other entries; left AppInit loading as-is
    )
)

:: --- Restore RequireSignedAppInit_DLLs ---
if "!HAS_BACKUP!"=="1" (
    if defined BAK_SIGNED (
        set /a "RESTORE_SIGNED=!BAK_SIGNED!" 2>nul
        reg add "%U_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d !RESTORE_SIGNED! /f >nul
        echo   Restored RequireSignedAppInit_DLLs from backup
    )
)

:: --- Delete DLL and backup file ---
if exist "%U_DLLPATH%" (
    del /f /q "%U_DLLPATH%" 2>nul
    if exist "%U_DLLPATH%" (
        echo   The DLL is still in use; it will be removable after a reboot: %U_DLLPATH%
    ) else (
        echo   Deleted %U_DLLNAME%
    )
)
if exist "%U_BACKUP%" del /f /q "%U_BACKUP%" 2>nul

endlocal
exit /b 0
