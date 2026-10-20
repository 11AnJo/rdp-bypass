@echo off
setlocal enabledelayedexpansion
title RdpBypass - Installer

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
set "SCRIPT_DIR=%~dp0"
set "HAS_ERROR=0"

:: AppInit_DLLs registry paths (32-bit = WOW6432Node, 64-bit = native)
set "KEY_WOW=HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
set "KEY_NATIVE=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"

:: Detect OS bitness (64-bit Windows defines ProgramFiles(x86))
set "OS64=0"
if defined ProgramFiles(x86) set "OS64=1"

:: Candidate DLLs (expected next to this script)
set "SRC32=%SCRIPT_DIR%RdpBypass32.dll"
set "SRC64=%SCRIPT_DIR%RdpBypass64.dll"

echo ============================================================
echo   RdpBypass - Installer (x86 + x64)
echo ============================================================
echo.
echo   Install dir: %INSTALL_DIR%
if "%OS64%"=="1" (echo   OS: 64-bit) else (echo   OS: 32-bit)
echo.

:: Need at least one DLL present
if not exist "%SRC32%" if not exist "%SRC64%" (
    echo [ERROR] RdpBypass32.dll / RdpBypass64.dll not found.
    echo         Keep this script in the same folder as the DLLs.
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  Create install directory
:: ============================================================
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to create directory: %INSTALL_DIR%
        set "HAS_ERROR=1"
        goto :done
    )
    echo [Install] Created directory: %INSTALL_DIR%
) else (
    echo [Skip] Directory already exists: %INSTALL_DIR%
)

:: ============================================================
::  Install 32-bit DLL
:: ============================================================
if exist "%SRC32%" (
    if "%OS64%"=="1" (
        call :install_arch "%SRC32%" "RdpBypass32.dll" "%KEY_WOW%" "backup32.reg.txt" "x86"
    ) else (
        call :install_arch "%SRC32%" "RdpBypass32.dll" "%KEY_NATIVE%" "backup32.reg.txt" "x86"
    )
    if errorlevel 1 set "HAS_ERROR=1"
)

:: ============================================================
::  Install 64-bit DLL (64-bit OS only)
:: ============================================================
if exist "%SRC64%" (
    if "%OS64%"=="1" (
        call :install_arch "%SRC64%" "RdpBypass64.dll" "%KEY_NATIVE%" "backup64.reg.txt" "x64"
        if errorlevel 1 set "HAS_ERROR=1"
    ) else (
        echo [Skip] 32-bit OS cannot load a 64-bit DLL; ignoring RdpBypass64.dll
    )
)

goto :done

:: ============================================================
::  Subroutine: install_arch  SRC  DLLNAME  KEY  BACKUPNAME  LABEL
:: ============================================================
:install_arch
setlocal enabledelayedexpansion
set "A_SRC=%~1"
set "A_DLLNAME=%~2"
set "A_KEY=%~3"
set "A_DLLPATH=%INSTALL_DIR%\%~2"
set "A_BACKUP=%INSTALL_DIR%\%~4"
set "A_LABEL=%~5"

echo.
echo ------------------------------------------------------------
echo   [%A_LABEL%] %A_DLLPATH%
echo   Registry: %A_KEY%
echo ------------------------------------------------------------

:: --- Back up current registry values (first time only) ---
if not exist "%A_BACKUP%" (
    echo # Registry backup created by RdpBypass Installer> "%A_BACKUP%"
    echo # Date: %date% %time%>> "%A_BACKUP%"
    for /f "tokens=2*" %%a in ('reg query "%A_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do echo AppInit_DLLs=%%b>> "%A_BACKUP%"
    for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v LoadAppInit_DLLs 2^>nul ^| findstr LoadAppInit_DLLs') do echo LoadAppInit_DLLs=%%a>> "%A_BACKUP%"
    for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v RequireSignedAppInit_DLLs 2^>nul ^| findstr RequireSignedAppInit_DLLs') do echo RequireSignedAppInit_DLLs=%%a>> "%A_BACKUP%"
    echo [Install] Backed up original registry values: %A_BACKUP%
) else (
    echo [Skip] Registry backup already exists
)

:: --- Copy DLL (idempotent) ---
fc /b "%A_SRC%" "%A_DLLPATH%" >nul 2>&1
if !errorlevel! neq 0 (
    copy /y "%A_SRC%" "%A_DLLPATH%" >nul
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to copy DLL
        endlocal
        exit /b 1
    )
    echo [Install] Copied DLL: %A_DLLPATH%
) else (
    echo [Skip] DLL already up to date
)

:: --- AppInit_DLLs (idempotent, prepend) ---
set "CUR_APPINIT="
for /f "tokens=2*" %%a in ('reg query "%A_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do set "CUR_APPINIT=%%b"
echo "!CUR_APPINIT!" | findstr /i /c:"%A_DLLPATH%" >nul 2>&1
if !errorlevel! neq 0 (
    if "!CUR_APPINIT!"=="" (
        reg add "%A_KEY%" /v AppInit_DLLs /t REG_SZ /d "%A_DLLPATH%" /f >nul
    ) else (
        reg add "%A_KEY%" /v AppInit_DLLs /t REG_SZ /d "%A_DLLPATH% !CUR_APPINIT!" /f >nul
    )
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to write AppInit_DLLs
        endlocal
        exit /b 1
    )
    echo [Install] AppInit_DLLs configured
) else (
    echo [Skip] AppInit_DLLs already contains the DLL path
)

:: --- LoadAppInit_DLLs = 1 ---
set "CUR_LOAD="
for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v LoadAppInit_DLLs 2^>nul ^| findstr LoadAppInit_DLLs') do set "CUR_LOAD=%%a"
if not "!CUR_LOAD!"=="0x1" (
    reg add "%A_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 1 /f >nul
    echo [Install] LoadAppInit_DLLs = 1
) else (
    echo [Skip] LoadAppInit_DLLs already 1
)

:: --- RequireSignedAppInit_DLLs = 0 ---
set "CUR_SIGNED="
for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v RequireSignedAppInit_DLLs 2^>nul ^| findstr RequireSignedAppInit_DLLs') do set "CUR_SIGNED=%%a"
if not "!CUR_SIGNED!"=="0x0" (
    reg add "%A_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d 0 /f >nul
    echo [Install] RequireSignedAppInit_DLLs = 0
) else (
    echo [Skip] RequireSignedAppInit_DLLs already 0
)

endlocal
exit /b 0

:: ============================================================
::  Finish
:: ============================================================
:done
echo.
echo ============================================================
if "%HAS_ERROR%"=="0" (
    echo   Install complete. Connect over RDP and launch the app.
    echo   Note: if Secure Boot is enabled, AppInit_DLLs is disabled by Windows.
) else (
    echo   Install finished WITH ERRORS. Check the [ERROR] lines above.
)
echo ============================================================
echo.
pause
