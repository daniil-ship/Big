typedef unsigned long long uint64_t;
typedef unsigned int uint32_t;
typedef int int32_t;
typedef unsigned short uint16_t;
typedef void* HANDLE;
typedef int BOOL;

#define NULL ((void*)0)
#define TRUE 1
#define FALSE 0
#define INFINITE 0xFFFFFFFF

typedef struct {
    uint32_t cb;
    char* lpReserved;
    char* lpDesktop;
    char* lpTitle;
    uint32_t dwX;
    uint32_t dwY;
    uint32_t dwXSize;
    uint32_t dwYSize;
    uint32_t dwXCountChars;
    uint32_t dwYCountChars;
    uint32_t dwFillAttribute;
    uint32_t dwFlags;
    uint16_t wShowWindow;
    uint16_t cbReserved2;
    void* lpReserved2;
    HANDLE hStdInput;
    HANDLE hStdOutput;
    HANDLE hStdError;
} STARTUPINFOA;

typedef struct {
    HANDLE hProcess;
    HANDLE hThread;
    uint32_t dwProcessId;
    uint32_t dwThreadId;
} PROCESS_INFORMATION;

typedef struct {
    HANDLE   (__attribute__((ms_abi)) *GetStdHandle)(int32_t nStdHandle);
    BOOL     (__attribute__((ms_abi)) *WriteFile)(HANDLE hFile, const void* lpBuf, uint32_t nBytes, uint32_t* lpWritten, void* lpOverlapped);
    void     (__attribute__((ms_abi)) *ExitProcess)(uint32_t uExitCode);
    BOOL     (__attribute__((ms_abi)) *CreateProcessA)(const char* lpApp, char* lpCmd, void* pSec, void* tSec, BOOL bInherit, uint32_t dwFlags, void* env, const char* dir, STARTUPINFOA* si, PROCESS_INFORMATION* pi);
    uint32_t (__attribute__((ms_abi)) *WaitForSingleObject)(HANDLE hHandle, uint32_t dwMilliseconds);
    BOOL     (__attribute__((ms_abi)) *GetExitCodeProcess)(HANDLE hProcess, uint32_t* lpExitCode);
    BOOL     (__attribute__((ms_abi)) *CloseHandle)(HANDLE hObject);
    char*    (__attribute__((ms_abi)) *GetCommandLineA)(void);
    uint32_t (__attribute__((ms_abi)) *GetModuleFileNameA)(HANDLE hModule, char* lpFilename, uint32_t nSize);
    BOOL     (__attribute__((ms_abi)) *SetConsoleOutputCP)(uint32_t wCodePageID);
    BOOL     (__attribute__((ms_abi)) *SetConsoleCP)(uint32_t wCodePageID);
} WinAPI;

static void my_strcat(char* dst, const char* src, uint32_t max_len) {
    uint32_t d = 0;
    while (dst[d] && d < max_len - 1) d++;
    uint32_t s = 0;
    while (src[s] && d < max_len - 1) {
        dst[d++] = src[s++];
    }
    dst[d] = '\0';
}

static BOOL try_spawn(WinAPI* api, char* full_cmd, uint32_t* exit_code) {
    STARTUPINFOA si;
    for (uint32_t i = 0; i < sizeof(si); i++) ((char*)&si)[i] = 0;
    si.cb = sizeof(si);
    si.dwFlags = 0x100; /* STARTF_USESTDHANDLES */
    si.hStdInput = api->GetStdHandle(-10);
    si.hStdOutput = api->GetStdHandle(-11);
    si.hStdError = api->GetStdHandle(-12);

    PROCESS_INFORMATION pi;
    for (uint32_t i = 0; i < sizeof(pi); i++) ((char*)&pi)[i] = 0;

    BOOL ok = api->CreateProcessA(NULL, full_cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
    if (!ok) return FALSE;

    api->WaitForSingleObject(pi.hProcess, INFINITE);
    api->GetExitCodeProcess(pi.hProcess, exit_code);
    api->CloseHandle(pi.hProcess);
    api->CloseHandle(pi.hThread);
    return TRUE;
}

void __attribute__((ms_abi)) launcher_entry(WinAPI* api) {
    api->SetConsoleOutputCP(65001);
    api->SetConsoleCP(65001);

    char* cmd = api->GetCommandLineA();
    while (*cmd == ' ' || *cmd == '\t') cmd++;
    if (*cmd == '"') {
        cmd++;
        while (*cmd && *cmd != '"') cmd++;
        if (*cmd == '"') cmd++;
    } else {
        while (*cmd && *cmd != ' ' && *cmd != '\t') cmd++;
    }
    while (*cmd == ' ' || *cmd == '\t') cmd++;

    char py_script[1024];
    for (uint32_t i = 0; i < sizeof(py_script); i++) py_script[i] = 0;

    uint32_t len = api->GetModuleFileNameA(NULL, py_script, sizeof(py_script) - 64);
    int last_slash = -1;
    for (uint32_t i = 0; i < len; i++) {
        if (py_script[i] == '\\' || py_script[i] == '/') {
            last_slash = (int)i;
        }
    }
    if (last_slash >= 0) {
        py_script[last_slash + 1] = '\0';
    } else {
        py_script[0] = '\0';
    }
    my_strcat(py_script, "bigc.py", sizeof(py_script));

    uint32_t exit_code = 0;
    char full_cmd[4096];

    /* Attempt 1: py -3 "<path>\bigc.py" <args> */
    full_cmd[0] = '\0';
    my_strcat(full_cmd, "py.exe -3 \"", sizeof(full_cmd));
    my_strcat(full_cmd, py_script, sizeof(full_cmd));
    my_strcat(full_cmd, "\" ", sizeof(full_cmd));
    my_strcat(full_cmd, cmd, sizeof(full_cmd));
    if (try_spawn(api, full_cmd, &exit_code)) {
        api->ExitProcess(exit_code);
    }

    /* Attempt 2: python "<path>\bigc.py" <args> */
    full_cmd[0] = '\0';
    my_strcat(full_cmd, "python.exe \"", sizeof(full_cmd));
    my_strcat(full_cmd, py_script, sizeof(full_cmd));
    my_strcat(full_cmd, "\" ", sizeof(full_cmd));
    my_strcat(full_cmd, cmd, sizeof(full_cmd));
    if (try_spawn(api, full_cmd, &exit_code)) {
        api->ExitProcess(exit_code);
    }

    /* Attempt 3: python3 "<path>\bigc.py" <args> */
    full_cmd[0] = '\0';
    my_strcat(full_cmd, "python3.exe \"", sizeof(full_cmd));
    my_strcat(full_cmd, py_script, sizeof(full_cmd));
    my_strcat(full_cmd, "\" ", sizeof(full_cmd));
    my_strcat(full_cmd, cmd, sizeof(full_cmd));
    if (try_spawn(api, full_cmd, &exit_code)) {
        api->ExitProcess(exit_code);
    }

    /* Attempt 4: cmd.exe /c py -3 "<path>\bigc.py" <args> */
    full_cmd[0] = '\0';
    my_strcat(full_cmd, "cmd.exe /c py -3 \"", sizeof(full_cmd));
    my_strcat(full_cmd, py_script, sizeof(full_cmd));
    my_strcat(full_cmd, "\" ", sizeof(full_cmd));
    my_strcat(full_cmd, cmd, sizeof(full_cmd));
    if (try_spawn(api, full_cmd, &exit_code)) {
        api->ExitProcess(exit_code);
    }

    /* Attempt 5: cmd.exe /c python "<path>\bigc.py" <args> */
    full_cmd[0] = '\0';
    my_strcat(full_cmd, "cmd.exe /c python \"", sizeof(full_cmd));
    my_strcat(full_cmd, py_script, sizeof(full_cmd));
    my_strcat(full_cmd, "\" ", sizeof(full_cmd));
    my_strcat(full_cmd, cmd, sizeof(full_cmd));
    if (try_spawn(api, full_cmd, &exit_code)) {
        api->ExitProcess(exit_code);
    }

    /* If all attempts fail, print instructions */
    static const char err_msg[] =
        "\r\n[ERROR] Python 3 was not found on your Windows system.\r\n"
        "The Big compiler requires Python 3.7+ to run.\r\n\r\n"
        "To install Python on Windows 11:\r\n"
        "  1. In PowerShell / Windows Terminal, run:\r\n"
        "     winget install Python.Python.3.12\r\n"
        "  2. Or download from: https://www.python.org/\r\n\r\n";
    HANDLE hErr = api->GetStdHandle(-12);
    uint32_t written = 0;
    api->WriteFile(hErr, err_msg, sizeof(err_msg) - 1, &written, NULL);
    api->ExitProcess(1);
}
