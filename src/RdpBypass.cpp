// RdpBypass - make an app believe it runs on the local console, not over RDP.
//
// Faked APIs (every other call passes through untouched):
//   user32!GetSystemMetrics(SM_REMOTESESSION)          -> 0      (not remote)
//   kernel32!WTSGetActiveConsoleSessionId()            -> our own session id
//   wtsapi32!WTSQuerySessionInformationW/A
//        (WTSClientProtocolType)                       -> 0      (console)
//
// Hooks are installed with Microsoft Detours from a worker thread (not DllMain),
// so loading wtsapi32 and patching happen outside the loader lock.

#include <windows.h>
#include <wtsapi32.h>
#include <detours.h>

typedef int(WINAPI *GetSystemMetrics_t)(int);
typedef DWORD(WINAPI *WTSGetActiveConsoleSessionId_t)(void);
typedef BOOL(WINAPI *WTSQuerySessionInformationW_t)(HANDLE, DWORD, WTS_INFO_CLASS, LPWSTR *, DWORD *);
typedef BOOL(WINAPI *WTSQuerySessionInformationA_t)(HANDLE, DWORD, WTS_INFO_CLASS, LPSTR *, DWORD *);

static GetSystemMetrics_t              TrueGetSystemMetrics = NULL;
static WTSGetActiveConsoleSessionId_t  TrueWTSGetActiveConsoleSessionId = NULL;
static WTSQuerySessionInformationW_t   TrueWTSQuerySessionInformationW = NULL;
static WTSQuerySessionInformationA_t   TrueWTSQuerySessionInformationA = NULL;

static int WINAPI FakeGetSystemMetrics(int nIndex) {
    if (nIndex == SM_REMOTESESSION) {
        return 0;
    }
    return TrueGetSystemMetrics(nIndex);
}

// Report the active console session as our own session, so an
// "am I on the console?" comparison succeeds.
static DWORD WINAPI FakeWTSGetActiveConsoleSessionId(void) {
    DWORD sid = 0;
    if (ProcessIdToSessionId(GetCurrentProcessId(), &sid)) {
        return sid;
    }
    if (TrueWTSGetActiveConsoleSessionId) {
        return TrueWTSGetActiveConsoleSessionId();
    }
    return 0;
}

// WTSClientProtocolType is 0 (console) / 1 (legacy) / 2 (RDP). Force it to 0.
static void PatchProtocolType(WTS_INFO_CLASS cls, void *buf, DWORD bytes) {
    if (cls == WTSClientProtocolType && buf && bytes >= sizeof(USHORT)) {
        *(USHORT *)buf = 0;
    }
}

static BOOL WINAPI FakeWTSQuerySessionInformationW(HANDLE hServer, DWORD sid,
                                                   WTS_INFO_CLASS cls,
                                                   LPWSTR *ppBuffer,
                                                   DWORD *pBytes) {
    BOOL r = TrueWTSQuerySessionInformationW(hServer, sid, cls, ppBuffer, pBytes);
    if (r && ppBuffer && pBytes) {
        PatchProtocolType(cls, *ppBuffer, *pBytes);
    }
    return r;
}

static BOOL WINAPI FakeWTSQuerySessionInformationA(HANDLE hServer, DWORD sid,
                                                   WTS_INFO_CLASS cls,
                                                   LPSTR *ppBuffer,
                                                   DWORD *pBytes) {
    BOOL r = TrueWTSQuerySessionInformationA(hServer, sid, cls, ppBuffer, pBytes);
    if (r && ppBuffer && pBytes) {
        PatchProtocolType(cls, *ppBuffer, *pBytes);
    }
    return r;
}

static DWORD WINAPI InstallThread(LPVOID) {
    HMODULE hUser32 = GetModuleHandleW(L"user32.dll");
    HMODULE hKernel32 = GetModuleHandleW(L"kernel32.dll");
    HMODULE hWts = LoadLibraryW(L"wtsapi32.dll"); // kept loaded on purpose

    TrueGetSystemMetrics = hUser32 ? (GetSystemMetrics_t)GetProcAddress(hUser32, "GetSystemMetrics") : NULL;
    TrueWTSGetActiveConsoleSessionId = hKernel32 ? (WTSGetActiveConsoleSessionId_t)GetProcAddress(hKernel32, "WTSGetActiveConsoleSessionId") : NULL;
    TrueWTSQuerySessionInformationW = hWts ? (WTSQuerySessionInformationW_t)GetProcAddress(hWts, "WTSQuerySessionInformationW") : NULL;
    TrueWTSQuerySessionInformationA = hWts ? (WTSQuerySessionInformationA_t)GetProcAddress(hWts, "WTSQuerySessionInformationA") : NULL;

    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    if (TrueGetSystemMetrics)
        DetourAttach(&(PVOID &)TrueGetSystemMetrics, (PVOID)FakeGetSystemMetrics);
    if (TrueWTSGetActiveConsoleSessionId)
        DetourAttach(&(PVOID &)TrueWTSGetActiveConsoleSessionId, (PVOID)FakeWTSGetActiveConsoleSessionId);
    if (TrueWTSQuerySessionInformationW)
        DetourAttach(&(PVOID &)TrueWTSQuerySessionInformationW, (PVOID)FakeWTSQuerySessionInformationW);
    if (TrueWTSQuerySessionInformationA)
        DetourAttach(&(PVOID &)TrueWTSQuerySessionInformationA, (PVOID)FakeWTSQuerySessionInformationA);
    DetourTransactionCommit();
    return 0;
}

static void RemoveHooks(void) {
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    if (TrueGetSystemMetrics)
        DetourDetach(&(PVOID &)TrueGetSystemMetrics, (PVOID)FakeGetSystemMetrics);
    if (TrueWTSGetActiveConsoleSessionId)
        DetourDetach(&(PVOID &)TrueWTSGetActiveConsoleSessionId, (PVOID)FakeWTSGetActiveConsoleSessionId);
    if (TrueWTSQuerySessionInformationW)
        DetourDetach(&(PVOID &)TrueWTSQuerySessionInformationW, (PVOID)FakeWTSQuerySessionInformationW);
    if (TrueWTSQuerySessionInformationA)
        DetourDetach(&(PVOID &)TrueWTSQuerySessionInformationA, (PVOID)FakeWTSQuerySessionInformationA);
    DetourTransactionCommit();
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD dwReason, LPVOID reserved) {
    if (DetourIsHelperProcess()) {
        return TRUE;
    }
    if (dwReason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hinst);
        DetourRestoreAfterWith();
        HANDLE h = CreateThread(NULL, 0, InstallThread, NULL, 0, NULL);
        if (h) {
            CloseHandle(h);
        }
    } else if (dwReason == DLL_PROCESS_DETACH) {
        if (reserved == NULL) {
            RemoveHooks();
        }
    }
    return TRUE;
}
