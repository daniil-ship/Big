.intel_syntax noprefix
.section .idata$2
    .long .Llookup - .L_image_base /* OriginalFirstThunk */
    .long 0                        /* TimeDateStamp */
    .long 0                        /* ForwarderChain */
    .long .Ldllname - .L_image_base /* Name */
    .long .Liat - .L_image_base    /* FirstThunk */

    /* Null descriptor */
    .long 0, 0, 0, 0, 0

.section .idata$4
.Llookup:
    .quad .Lhint_GetStdHandle - .L_image_base
    .quad .Lhint_WriteFile - .L_image_base
    .quad .Lhint_ExitProcess - .L_image_base
    .quad .Lhint_CreateProcessA - .L_image_base
    .quad .Lhint_WaitForSingleObject - .L_image_base
    .quad .Lhint_GetExitCodeProcess - .L_image_base
    .quad .Lhint_CloseHandle - .L_image_base
    .quad .Lhint_GetCommandLineA - .L_image_base
    .quad .Lhint_GetModuleFileNameA - .L_image_base
    .quad .Lhint_SetConsoleOutputCP - .L_image_base
    .quad .Lhint_SetConsoleCP - .L_image_base
    .quad 0

.section .idata$5
.Liat:
.global iat_winapi
iat_winapi:
    .quad .Lhint_GetStdHandle - .L_image_base
    .quad .Lhint_WriteFile - .L_image_base
    .quad .Lhint_ExitProcess - .L_image_base
    .quad .Lhint_CreateProcessA - .L_image_base
    .quad .Lhint_WaitForSingleObject - .L_image_base
    .quad .Lhint_GetExitCodeProcess - .L_image_base
    .quad .Lhint_CloseHandle - .L_image_base
    .quad .Lhint_GetCommandLineA - .L_image_base
    .quad .Lhint_GetModuleFileNameA - .L_image_base
    .quad .Lhint_SetConsoleOutputCP - .L_image_base
    .quad .Lhint_SetConsoleCP - .L_image_base
    .quad 0

.section .idata$6
.Lhint_GetStdHandle:
    .short 0
    .asciz "GetStdHandle"
.Lhint_WriteFile:
    .short 0
    .asciz "WriteFile"
.Lhint_ExitProcess:
    .short 0
    .asciz "ExitProcess"
.Lhint_CreateProcessA:
    .short 0
    .asciz "CreateProcessA"
.Lhint_WaitForSingleObject:
    .short 0
    .asciz "WaitForSingleObject"
.Lhint_GetExitCodeProcess:
    .short 0
    .asciz "GetExitCodeProcess"
.Lhint_CloseHandle:
    .short 0
    .asciz "CloseHandle"
.Lhint_GetCommandLineA:
    .short 0
    .asciz "GetCommandLineA"
.Lhint_GetModuleFileNameA:
    .short 0
    .asciz "GetModuleFileNameA"
.Lhint_SetConsoleOutputCP:
    .short 0
    .asciz "SetConsoleOutputCP"
.Lhint_SetConsoleCP:
    .short 0
    .asciz "SetConsoleCP"

.section .idata$7
.Ldllname:
    .asciz "KERNEL32.DLL"

.section .text
.global _start
.equ .L_image_base, 0x140000000
_start:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rcx, [rip + iat_winapi]
    call launcher_entry
    add rsp, 32
    pop rbp
    ret
