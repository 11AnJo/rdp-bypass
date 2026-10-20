# RdpBypass

Makes Windows report your Remote Desktop session as a local console session.

Some Windows software refuses to run over RDP. It asks Windows whether the session is remote and quits if it is. RdpBypass is a small hook DLL that intercepts the APIs used for that check and reports a local console session instead, so the software runs over Remote Desktop.

Use it only on machines and software you're allowed to use this way. Defeating a vendor's remote-access check can breach that software's license terms.

## What it hooks

The DLL loads into each process and only changes these calls. Everything else is passed straight through to the real function.

| API | Normally | With RdpBypass |
|-----|----------|----------------|
| `GetSystemMetrics(SM_REMOTESESSION)` | 1 when remote | 0 (local) |
| `WTSGetActiveConsoleSessionId()` | the console's session id | your session id |
| `WTSQuerySessionInformation(... ClientProtocolType)` | 2 (RDP) | 0 (console) |

## Install

1. Get `RdpBypass32.dll`, `RdpBypass64.dll`, `Install.bat`, `Uninstall.bat` (from a release, or build them below).
2. Right-click `Install.bat`, Run as administrator.
3. Reboot. The check usually runs inside a background license service that only loads the hook after a restart.

To remove it, run `Uninstall.bat` as administrator. It restores the registry values it backed up at install time.

## How it loads

Windows loads DLLs listed under the `AppInit_DLLs` registry value into every process that uses `user32.dll`, before the process's own startup code runs. The installer registers the x86 DLL under the 32-bit key and the x64 DLL under the native key, so 32-bit and 64-bit apps are both covered.

## Requirements

- Administrator rights to install (it writes to HKLM).
- Secure Boot must be off. Windows ignores `AppInit_DLLs` when Secure Boot is on, so the DLL won't load. Check with `Confirm-SecureBootUEFI` in an admin PowerShell; `False` is what you want.
- Antivirus may flag global DLL injection. Whitelist `C:\RdpBypass\` if needed.

If an app still blocks you after this, it's detecting RDP some other way (a dongle runtime, checking for `rdpclip.exe`, reading Terminal Server registry flags). The source is short and easy to add another hook to.

## Build

GitHub Actions builds both architectures on each push and attaches a zip to the GitHub Release when you push a tag (`v*`). The output depends only on kernel32, user32 and msvcrt.

To build locally on Windows: clone [Microsoft Detours](https://github.com/microsoft/Detours), build it, then compile `src/RdpBypass.cpp` against it with the Visual Studio C++ toolchain (x86 and x64). The workflow in `.github/workflows/build.yml` has the exact commands.

## License

MIT, see [LICENSE](LICENSE). Uses [Microsoft Detours](https://github.com/microsoft/Detours) (MIT). Derived from the pads-rdp-bypass project.
