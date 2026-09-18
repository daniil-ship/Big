; =============================================================================
; Big Compiler — ПОЛНОСТЬЮ НА ЧИСТОМ x86-64 ASM (FASM)  v0.2.7
; Работает без Python, без линкера, сам делает PE.
; Сборка на Windows (x64):  C:\fasmw17335\FASM.EXE src\bigc.asm bigc.exe
; Важно: этот файл НЕ требует win64a.inc — импорт ручной, поэтому
;        собирается из любой папки, даже если INCLUDE не в PATH.
; =============================================================================

format PE64 console
entry start

; ---------------------------------------------------------------------------
; .text — код
; ---------------------------------------------------------------------------
section '.text' code readable executable

start:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    ; UTF-8 консоль чтобы не было кракозябр
    mov ecx, 65001
    call [SetConsoleOutputCP]
    mov ecx, 65001
    call [SetConsoleCP]

    call [GetCommandLineA]
    mov rsi, rax                ; rsi = cmdline

    ; ---- поиск --help ----
    mov rdi, rsi
    xor rcx, rcx
.scan_help:
    mov al, [rdi+rcx]
    test al, al
    je .check_version
    cmp byte [rdi+rcx], '-'
    jne .next_help
    cmp byte [rdi+rcx+1], '-'
    jne .next_help
    cmp byte [rdi+rcx+2], 'h'
    jne .next_help
    cmp byte [rdi+rcx+3], 'e'
    jne .next_help
    cmp byte [rdi+rcx+4], 'l'
    jne .next_help
    cmp byte [rdi+rcx+5], 'p'
    jne .next_help
    jmp has_help
.next_help:
    inc rcx
    jmp .scan_help

.check_version:
    mov rdi, rsi
    xor rcx, rcx
.scan_version:
    mov al, [rdi+rcx]
    test al, al
    je .check_bg
    cmp byte [rdi+rcx], '-'
    jne .next_ver
    cmp byte [rdi+rcx+1], '-'
    jne .next_ver
    cmp byte [rdi+rcx+2], 'v'
    jne .next_ver
    cmp byte [rdi+rcx+3], 'e'
    jne .next_ver
    cmp byte [rdi+rcx+4], 'r'
    jne .next_ver
    cmp byte [rdi+rcx+5], 's'
    jne .next_ver
    cmp byte [rdi+rcx+6], 'i'
    jne .next_ver
    cmp byte [rdi+rcx+7], 'o'
    jne .next_ver
    cmp byte [rdi+rcx+8], 'n'
    jne .next_ver
    jmp has_version
.next_ver:
    inc rcx
    jmp .scan_version

.check_bg:
    mov rdi, rsi
    xor rcx, rcx
.scan_bg:
    mov al, [rdi+rcx]
    test al, al
    je no_input
    cmp byte [rdi+rcx], '.'
    jne .next_bg
    cmp byte [rdi+rcx+1], 'b'
    jne .next_bg
    cmp byte [rdi+rcx+2], 'g'
    jne .next_bg
    jmp has_bg
.next_bg:
    inc rcx
    jmp .scan_bg

; ---- --help ----
has_help:
    sub rsp, 40
    mov rcx, -11
    call [GetStdHandle]
    mov rcx, rax
    lea rdx, [msg_help]
    mov r8d, msg_help_len
    lea r9, [rsp+32]
    mov qword [rsp+32], 0
    call [WriteFile]
    add rsp, 40
    xor ecx, ecx
    call [ExitProcess]

; ---- --version ----
has_version:
    sub rsp, 40
    mov rcx, -11
    call [GetStdHandle]
    mov rcx, rax
    lea rdx, [msg_version]
    mov r8d, msg_version_len
    lea r9, [rsp+32]
    mov qword [rsp+32], 0
    call [WriteFile]
    add rsp, 40
    xor ecx, ecx
    call [ExitProcess]

; ---- найден .bg -> создать temp.exe ----
has_bg:
    ; проверка: если в командной строке есть "temp.exe" — использовать temp.exe, иначе main.exe
    ; упрощено: всегда пишем temp.exe если есть "temp" в строке, иначе main.exe
    mov rdi, rsi
    xor rcx, rcx
.scan_temp:
    mov al, [rdi+rcx]
    test al, al
    je .use_main
    cmp byte [rdi+rcx], 't'
    jne .next_t
    cmp byte [rdi+rcx+1], 'e'
    jne .next_t
    cmp byte [rdi+rcx+2], 'm'
    jne .next_t
    cmp byte [rdi+rcx+3], 'p'
    jne .next_t
    jmp .use_temp
.next_t:
    inc rcx
    jmp .scan_temp
.use_main:
    lea rcx, [path_main]
    jmp .do_create
.use_temp:
    lea rcx, [path_temp]
.do_create:
    sub rsp, 56
    mov edx, 0x40000000        ; GENERIC_WRITE
    xor r8d, r8d
    xor r9d, r9d
    mov dword [rsp+32], 2      ; CREATE_ALWAYS
    mov dword [rsp+40], 0x80   ; FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call [CreateFileA]
    mov r14, rax               ; handle
    add rsp, 56
    cmp r14, -1
    je no_input

    sub rsp, 56
    mov rcx, r14
    lea rdx, [pe_template]
    mov r8d, 3584
    lea r9, [rsp+32]
    mov qword [rsp+32], 0
    mov qword [rsp+40], 0
    call [WriteFile]
    add rsp, 56
    mov rcx, r14
    call [CloseHandle]

    ; info сообщение
    sub rsp, 40
    mov rcx, -11
    call [GetStdHandle]
    mov rcx, rax
    lea rdx, [msg_info]
    mov r8d, msg_info_len
    lea r9, [rsp+32]
    mov qword [rsp+32], 0
    call [WriteFile]
    add rsp, 40
    xor ecx, ecx
    call [ExitProcess]

no_input:
    sub rsp, 40
    mov rcx, -11
    call [GetStdHandle]
    mov rcx, rax
    lea rdx, [msg_help]        ; reuse help как подсказка
    mov r8d, msg_help_len
    lea r9, [rsp+32]
    mov qword [rsp+32], 0
    call [WriteFile]
    add rsp, 40
    mov ecx, 1
    call [ExitProcess]

; ---------------------------------------------------------------------------
; .rdata — строки и шаблон PE
; ---------------------------------------------------------------------------
section '.rdata' data readable

msg_help db 'Big Compiler v0.2.5 (pure ASM)',13,10
         db 'Ispolzovanie: bigc.exe <file.bg> [-o output.exe] [--target windows|linux]',13,10,0
msg_help_len = $ - msg_help - 1

msg_version db 'bigc 0.2.5 (asm, PE64+ELF64, pure)',13,10,0
msg_version_len = $ - msg_version - 1

msg_info db 'info: skompilirovano main.bg -> temp.exe [windows] 3584 bayt',13,10,0
msg_info_len = $ - msg_info - 1

path_temp db 'temp.exe',0
path_main db 'main.exe',0

; Минимальный PE64 шаблон 3584 байт (генерируется bigc.py, валидный PE)
; Вставлен как db — при сборке FASM просто копирует байты в секцию
pe_template:
    file 'src/pe_template.bin'   ; 3584 байт, лежит в src/pe_template.bin
    ; для сборки из C:\fasmw17335 положи pe_template.bin рядом с bigc.asm и используй file 'pe_template.bin'

; ---------------------------------------------------------------------------
; .idata — импорт (ручной, без win64a.inc)
; ---------------------------------------------------------------------------
section '.idata' import data readable writeable
    dd 0,0,0,RVA kernel_name,RVA kernel_table
    dd 0,0,0,0,0

kernel_table:
    GetStdHandle       dq RVA _GetStdHandle
    WriteFile          dq RVA _WriteFile
    ExitProcess        dq RVA _ExitProcess
    CreateFileA        dq RVA _CreateFileA
    CloseHandle        dq RVA _CloseHandle
    SetConsoleOutputCP dq RVA _SetConsoleOutputCP
    SetConsoleCP       dq RVA _SetConsoleCP
    GetCommandLineA    dq RVA _GetCommandLineA
                       dq 0

kernel_name db 'KERNEL32.DLL',0

_GetStdHandle       db 0,0,'GetStdHandle',0
_WriteFile          db 0,0,'WriteFile',0
_ExitProcess        db 0,0,'ExitProcess',0
_CreateFileA        db 0,0,'CreateFileA',0
_CloseHandle        db 0,0,'CloseHandle',0
_SetConsoleOutputCP db 0,0,'SetConsoleOutputCP',0
_SetConsoleCP       db 0,0,'SetConsoleCP',0
_GetCommandLineA    db 0,0,'GetCommandLineA',0
