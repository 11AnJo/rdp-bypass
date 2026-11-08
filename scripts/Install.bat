@echo off
setlocal enabledelayedexpansion
title RdpBypass - Installer

:: ============================================================
::  Require administrator privileges
:: ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo This installer needs administrator rights because it writes to HKEY_LOCAL_MACHINE.
    echo Please close this window and run Install.bat again via right-click -^> Run as administrator.
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

:: Need at least one DLL present
if not exist "%SRC32%" if not exist "%SRC64%" (
    echo Could not find RdpBypass32.dll or RdpBypass64.dll next to this script.
    echo Put Install.bat in the same folder as the DLLs and run it again.
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  Explain what will happen, then ask for consent
:: ============================================================
echo ============================================================
echo   RdpBypass  -  run software over Remote Desktop
echo ============================================================
echo.
echo   Some programs refuse to run in a Remote Desktop session.
echo   RdpBypass loads a small DLL that makes Windows report your
echo   session as a local console, so those programs start normally.
echo   It is open source under the MIT license.
echo.
echo   This installer will:
echo     1. Copy the hook DLL(s) into %INSTALL_DIR%
echo     2. Register them with the Windows AppInit_DLLs mechanism, by
echo        setting these values under HKLM...\Windows NT\CurrentVersion\Windows:
echo          - AppInit_DLLs                 (adds the DLL path)
echo          - LoadAppInit_DLLs = 1         (enables AppInit loading)
echo          - RequireSignedAppInit_DLLs = 0 (allows the unsigned DLL to load)
echo.
echo   Before changing anything it saves the current values to a backup
echo   file, and Uninstall.bat restores them and removes the files.
echo.
if "%OS64%"=="1" (echo   Detected: 64-bit Windows) else (echo   Detected: 32-bit Windows)
echo.
set /p "CONFIRM=Type Y to install, or anything else to cancel: "
if /i not "%CONFIRM%"=="Y" (
    echo.
    echo Cancelled. Nothing was changed.
    echo.
    pause
    exit /b 0
)
echo.

:: ============================================================
::  Create install directory
:: ============================================================
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    if !errorlevel! neq 0 (
        echo Could not create the install folder: %INSTALL_DIR%
        set "HAS_ERROR=1"
        goto :done
    )
    echo Created install folder: %INSTALL_DIR%
) else (
    echo Install folder already exists: %INSTALL_DIR%
)

:: ============================================================
::  Install 32-bit DLL
:: ============================================================
if exist "%SRC32%" (
    if "%OS64%"=="1" (
        call :install_arch "%SRC32%" "RdpBypass32.dll" "%KEY_WOW%" "backup32.reg.txt" "32-bit apps"
    ) else (
        call :install_arch "%SRC32%" "RdpBypass32.dll" "%KEY_NATIVE%" "backup32.reg.txt" "32-bit apps"
    )
    if errorlevel 1 set "HAS_ERROR=1"
)

:: ============================================================
::  Install 64-bit DLL (64-bit OS only)
:: ============================================================
if exist "%SRC64%" (
    if "%OS64%"=="1" (
        call :install_arch "%SRC64%" "RdpBypass64.dll" "%KEY_NATIVE%" "backup64.reg.txt" "64-bit apps"
        if errorlevel 1 set "HAS_ERROR=1"
    ) else (
        echo Skipping RdpBypass64.dll: a 32-bit Windows cannot load a 64-bit DLL.
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
echo --- Setting up the hook for %A_LABEL% (%A_DLLNAME%) ---

:: --- Back up current registry values (first time only) ---
if not exist "%A_BACKUP%" (
    echo # Registry backup created by RdpBypass Installer> "%A_BACKUP%"
    echo # Date: %date% %time%>> "%A_BACKUP%"
    for /f "tokens=2*" %%a in ('reg query "%A_KEY%" /v AppInit_DLLs 2^>nul ^| findstr AppInit_DLLs') do echo AppInit_DLLs=%%b>> "%A_BACKUP%"
    for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v LoadAppInit_DLLs 2^>nul ^| findstr LoadAppInit_DLLs') do echo LoadAppInit_DLLs=%%a>> "%A_BACKUP%"
    for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v RequireSignedAppInit_DLLs 2^>nul ^| findstr RequireSignedAppInit_DLLs') do echo RequireSignedAppInit_DLLs=%%a>> "%A_BACKUP%"
    echo   Saved current registry values to %A_BACKUP%
) else (
    echo   Registry backup already exists, keeping it
)

:: --- Copy DLL (idempotent) ---
fc /b "%A_SRC%" "%A_DLLPATH%" >nul 2>&1
if !errorlevel! neq 0 (
    copy /y "%A_SRC%" "%A_DLLPATH%" >nul
    if !errorlevel! neq 0 (
        echo   Could not copy the DLL to %A_DLLPATH%
        endlocal
        exit /b 1
    )
    echo   Copied %A_DLLNAME% to %INSTALL_DIR%
) else (
    echo   %A_DLLNAME% is already up to date
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
        echo   Could not update AppInit_DLLs
        endlocal
        exit /b 1
    )
    echo   Registered the DLL in AppInit_DLLs
) else (
    echo   AppInit_DLLs already lists this DLL
)

:: --- LoadAppInit_DLLs = 1 ---
set "CUR_LOAD="
for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v LoadAppInit_DLLs 2^>nul ^| findstr LoadAppInit_DLLs') do set "CUR_LOAD=%%a"
if not "!CUR_LOAD!"=="0x1" (
    reg add "%A_KEY%" /v LoadAppInit_DLLs /t REG_DWORD /d 1 /f >nul
    echo   Enabled AppInit loading (LoadAppInit_DLLs = 1)
) else (
    echo   AppInit loading already enabled
)

:: --- RequireSignedAppInit_DLLs = 0 ---
set "CUR_SIGNED="
for /f "tokens=3" %%a in ('reg query "%A_KEY%" /v RequireSignedAppInit_DLLs 2^>nul ^| findstr RequireSignedAppInit_DLLs') do set "CUR_SIGNED=%%a"
if not "!CUR_SIGNED!"=="0x0" (
    reg add "%A_KEY%" /v RequireSignedAppInit_DLLs /t REG_DWORD /d 0 /f >nul
    echo   Allowed the unsigned DLL to load (RequireSignedAppInit_DLLs = 0)
) else (
    echo   Unsigned AppInit DLLs already allowed
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
    echo   Done. RdpBypass is installed.
    echo.
    echo   Reboot before using it, so already-running programs and
    echo   services pick up the hook. Then connect over RDP and start
    echo   your app as usual.
    echo.
    echo   To remove everything later, run Uninstall.bat as administrator.
    echo   If Secure Boot is on, Windows ignores AppInit_DLLs and the hook
    echo   will not load; turn Secure Boot off for it to take effect.
) else (
    echo   Finished, but one or more steps failed. See the messages above.
    echo   You can run Uninstall.bat to undo any partial changes.
)
echo ============================================================
echo.
pause
