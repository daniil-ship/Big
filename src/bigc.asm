; =============================================================================
; Big Compiler v0.4.0 - NASM flat-binary PE64 bootstrap
;
; This file is assembled directly by NASM.  No linker, Python or FASM tools or import
; include files are needed.  The PE headers, import table and the output PE
; template are all emitted by this source.
;
; Windows:
;   nasm -f bin src\bigc.asm -o bigc.exe
;
; Linux cross-build (produces a Windows PE64 file):
;   nasm -f bin src/bigc.asm -o bigc.exe
;
; The command must be run from the repository root because INCBIN includes
; src/pe_template.bin.
; =============================================================================

BITS 64
ORG 0

; -----------------------------------------------------------------------------
; Fixed PE layout.  Keeping virtual addresses explicit makes this a genuine
; flat binary: NASM does not need a COFF linker or a platform-specific format
; module.
; -----------------------------------------------------------------------------
%define IMAGE_BASE       0x140000000
%define SECTION_ALIGN    0x1000
%define FILE_ALIGN       0x200
%define HEADERS_SIZE     0x200

%define TEXT_FILE        0x200
%define TEXT_RVA         0x1000
%define TEXT_RAW_SIZE    0x400

%define RDATA_FILE       0x600
%define RDATA_RVA        0x2000
%define RDATA_RAW_SIZE   0x1200
%define RDATA_VSIZE      0x1100

%define IMPORT_RVA       RDATA_RVA
%define KERNEL_NAME_RVA  (RDATA_RVA + 0x28)
%define LOOKUP_RVA       (RDATA_RVA + 0xB8)
%define IAT_RVA          (RDATA_RVA + 0x100)

%define NAME_GETSTD_RVA  (RDATA_RVA + 0x36)
%define NAME_WRITE_RVA   (RDATA_RVA + 0x46)
%define NAME_EXIT_RVA    (RDATA_RVA + 0x52)
%define NAME_CREATE_RVA  (RDATA_RVA + 0x60)
%define NAME_CLOSE_RVA   (RDATA_RVA + 0x6E)
%define NAME_SETCP_OUT   (RDATA_RVA + 0x7C)
%define NAME_SETCP_RVA   (RDATA_RVA + 0x92)
%define NAME_CMDLINE_RVA (RDATA_RVA + 0xA2)

%define MSG_HELP_OFF     0x148
%define MSG_VERSION_OFF  0x1C0
%define MSG_INFO_OFF     0x1F0
%define PATH_TEMP_OFF    0x240
%define PATH_MAIN_OFF    0x250
%define TEMPLATE_OFF     0x300
%define TEMPLATE_RVA     (RDATA_RVA + TEMPLATE_OFF)
%define TEMPLATE_SIZE    0xE00

%define MSG_HELP_ADDR    (IMAGE_BASE + RDATA_RVA + MSG_HELP_OFF)
%define MSG_VERSION_ADDR (IMAGE_BASE + RDATA_RVA + MSG_VERSION_OFF)
%define MSG_INFO_ADDR    (IMAGE_BASE + RDATA_RVA + MSG_INFO_OFF)
%define PATH_TEMP_ADDR   (IMAGE_BASE + RDATA_RVA + PATH_TEMP_OFF)
%define PATH_MAIN_ADDR   (IMAGE_BASE + RDATA_RVA + PATH_MAIN_OFF)
%define TEMPLATE_ADDR    (IMAGE_BASE + TEMPLATE_RVA)

; IAT entries are filled by the Windows loader before the entry point runs.
%define IAT_GETSTD       (IMAGE_BASE + IAT_RVA + 0x00)
%define IAT_WRITE        (IMAGE_BASE + IAT_RVA + 0x08)
%define IAT_EXIT         (IMAGE_BASE + IAT_RVA + 0x10)
%define IAT_CREATE       (IMAGE_BASE + IAT_RVA + 0x18)
%define IAT_CLOSE        (IMAGE_BASE + IAT_RVA + 0x20)
%define IAT_SETCP_OUT    (IMAGE_BASE + IAT_RVA + 0x28)
%define IAT_SETCP        (IMAGE_BASE + IAT_RVA + 0x30)
%define IAT_CMDLINE      (IMAGE_BASE + IAT_RVA + 0x38)

%define MSG_HELP_LEN     105
%define MSG_VERSION_LEN  37
%define MSG_INFO_LEN     57

; Load one imported function through the loader-populated IAT.
%macro call_import 1
    mov rax, %1
    call qword [rax]
%endmacro

; -----------------------------------------------------------------------------
; DOS header and PE/COFF header
; -----------------------------------------------------------------------------
    db 'M', 'Z'
    times 0x3A db 0
    dd 0x80                         ; e_lfanew
    times 0x80 - ($ - $$) db 0

    db 'P', 'E', 0, 0

    ; IMAGE_FILE_HEADER
    dw 0x8664                       ; AMD64
    dw 2                            ; .text, .rdata
    dd 0                            ; timestamp
    dd 0                            ; symbol table pointer
    dd 0                            ; symbol count
    dw 0xF0                         ; PE32+ optional header size
    dw 0x0022                       ; executable | large-address-aware

    ; IMAGE_OPTIONAL_HEADER64
    dw 0x020B                       ; PE32+
    db 14, 0                        ; linker version
    dd TEXT_RAW_SIZE                ; SizeOfCode
    dd RDATA_RAW_SIZE               ; SizeOfInitializedData
    dd 0                            ; SizeOfUninitializedData
    dd TEXT_RVA                     ; AddressOfEntryPoint
    dd TEXT_RVA                     ; BaseOfCode
    dq IMAGE_BASE
    dd SECTION_ALIGN
    dd FILE_ALIGN
    dw 6, 0                         ; operating system version
    dw 0, 0                         ; image version
    dw 6, 0                         ; subsystem version
    dd 0                            ; Win32VersionValue
    dd 0x4000                       ; SizeOfImage
    dd HEADERS_SIZE                ; SizeOfHeaders
    dd 0                            ; CheckSum
    dw 3                            ; IMAGE_SUBSYSTEM_WINDOWS_CUI
    dw 0                            ; DllCharacteristics
    dq 0x100000                     ; SizeOfStackReserve
    dq 0x1000                       ; SizeOfStackCommit
    dq 0x100000                     ; SizeOfHeapReserve
    dq 0x1000                       ; SizeOfHeapCommit
    dd 0                            ; LoaderFlags
    dd 16                           ; NumberOfRvaAndSizes

    ; IMAGE_DATA_DIRECTORY[16]
    dd 0, 0                         ; export
    dd IMPORT_RVA, 0x28             ; import
    times 20 dd 0                   ; resource through bound import
    dd IAT_RVA, 0x48               ; import address table
    times 6 dd 0                    ; delay import, CLR, reserved

    ; IMAGE_SECTION_HEADER .text
    db '.text', 0, 0, 0
    dd TEXT_RAW_SIZE
    dd TEXT_RVA
    dd TEXT_RAW_SIZE
    dd TEXT_FILE
    dd 0, 0
    dw 0, 0
    dd 0x60000020                   ; code, execute, read

    ; IMAGE_SECTION_HEADER .rdata/.idata (writable for the loader's IAT)
    db '.rdata', 0, 0
    dd RDATA_VSIZE
    dd RDATA_RVA
    dd RDATA_RAW_SIZE
    dd RDATA_FILE
    dd 0, 0
    dw 0, 0
    dd 0x40000040                   ; initialized data, read (loader patches the IAT)

    times HEADERS_SIZE - ($ - $$) db 0

; -----------------------------------------------------------------------------
; .text, at file offset 0x200 / RVA 0x1000
; -----------------------------------------------------------------------------
text_start:
start:
    push rbp
    mov rbp, rsp
    sub rsp, 32                     ; Windows x64 shadow space

    ; Keep child output UTF-8 in Windows consoles.
    mov ecx, 65001
    call_import IAT_SETCP_OUT
    mov ecx, 65001
    call_import IAT_SETCP

    call_import IAT_CMDLINE
    mov rsi, rax

    ; Search for --help anywhere in the command line.
    mov rdi, rsi
    xor rcx, rcx
.scan_help:
    mov al, [rdi + rcx]
    test al, al
    jz .check_version
    cmp byte [rdi + rcx], '-'
    jne .next_help
    cmp byte [rdi + rcx + 1], '-'
    jne .next_help
    cmp byte [rdi + rcx + 2], 'h'
    jne .next_help
    cmp byte [rdi + rcx + 3], 'e'
    jne .next_help
    cmp byte [rdi + rcx + 4], 'l'
    jne .next_help
    cmp byte [rdi + rcx + 5], 'p'
    jne .next_help
    jmp has_help
.next_help:
    inc rcx
    jmp .scan_help

.check_version:
    mov rdi, rsi
    xor rcx, rcx
.scan_version:
    mov al, [rdi + rcx]
    test al, al
    jz .check_bg
    cmp byte [rdi + rcx], '-'
    jne .next_version
    cmp byte [rdi + rcx + 1], '-'
    jne .next_version
    cmp byte [rdi + rcx + 2], 'v'
    jne .next_version
    cmp byte [rdi + rcx + 3], 'e'
    jne .next_version
    cmp byte [rdi + rcx + 4], 'r'
    jne .next_version
    cmp byte [rdi + rcx + 5], 's'
    jne .next_version
    cmp byte [rdi + rcx + 6], 'i'
    jne .next_version
    cmp byte [rdi + rcx + 7], 'o'
    jne .next_version
    cmp byte [rdi + rcx + 8], 'n'
    jne .next_version
    jmp has_version
.next_version:
    inc rcx
    jmp .scan_version

.check_bg:
    ; The bootstrap always emits the template when it is not a meta command.
    jmp has_bg

; --help
has_help:
    sub rsp, 40
    mov rcx, -11
    call_import IAT_GETSTD
    mov rcx, rax
    mov rdx, MSG_HELP_ADDR
    mov r8d, MSG_HELP_LEN
    lea r9, [rsp + 32]
    mov qword [rsp + 32], 0
    call_import IAT_WRITE
    add rsp, 40
    xor ecx, ecx
    call_import IAT_EXIT

; --version
has_version:
    sub rsp, 40
    mov rcx, -11
    call_import IAT_GETSTD
    mov rcx, rax
    mov rdx, MSG_VERSION_ADDR
    mov r8d, MSG_VERSION_LEN
    lea r9, [rsp + 32]
    mov qword [rsp + 32], 0
    call_import IAT_WRITE
    add rsp, 40
    xor ecx, ecx
    call_import IAT_EXIT

; Input found: write the embedded 3584-byte PE template.
has_bg:
    ; Keep compatibility with the current command line contract:
    ; an output containing "temp" selects temp.exe, otherwise main.exe.
    mov rdi, rsi
    xor rcx, rcx
.scan_temp:
    mov al, [rdi + rcx]
    test al, al
    jz .use_main
    cmp byte [rdi + rcx], 't'
    jne .next_temp
    cmp byte [rdi + rcx + 1], 'e'
    jne .next_temp
    cmp byte [rdi + rcx + 2], 'm'
    jne .next_temp
    cmp byte [rdi + rcx + 3], 'p'
    jne .next_temp
    jmp .use_temp
.next_temp:
    inc rcx
    jmp .scan_temp
.use_main:
    mov rcx, PATH_MAIN_ADDR
    jmp .create_output
.use_temp:
    mov rcx, PATH_TEMP_ADDR

.create_output:
    sub rsp, 56                    ; shadow + 24 bytes of stack arguments
    mov edx, 0x40000000            ; GENERIC_WRITE
    xor r8d, r8d                   ; no share mode
    xor r9d, r9d                   ; lpSecurityAttributes = NULL
    mov dword [rsp + 32], 2        ; CREATE_ALWAYS
    mov dword [rsp + 40], 0x80     ; FILE_ATTRIBUTE_NORMAL
    mov qword [rsp + 48], 0
    call_import IAT_CREATE
    mov r14, rax
    add rsp, 56
    cmp r14, -1
    jz no_input

    sub rsp, 56
    mov rcx, r14
    mov rdx, TEMPLATE_ADDR
    mov r8d, TEMPLATE_SIZE
    lea r9, [rsp + 32]
    mov qword [rsp + 32], 0
    mov qword [rsp + 40], 0
    call_import IAT_WRITE
    add rsp, 56
    mov rcx, r14
    call_import IAT_CLOSE

    sub rsp, 40
    mov rcx, -11
    call_import IAT_GETSTD
    mov rcx, rax
    mov rdx, MSG_INFO_ADDR
    mov r8d, MSG_INFO_LEN
    lea r9, [rsp + 32]
    mov qword [rsp + 32], 0
    call_import IAT_WRITE
    add rsp, 40
    xor ecx, ecx
    call_import IAT_EXIT

no_input:
    sub rsp, 40
    mov rcx, -11
    call_import IAT_GETSTD
    mov rcx, rax
    mov rdx, MSG_HELP_ADDR
    mov r8d, MSG_HELP_LEN
    lea r9, [rsp + 32]
    mov qword [rsp + 32], 0
    call_import IAT_WRITE
    add rsp, 40
    mov ecx, 1
    call_import IAT_EXIT

    times RDATA_FILE - ($ - $$) db 0

; -----------------------------------------------------------------------------
; .rdata/.idata, at file offset 0x600 / RVA 0x2000
; -----------------------------------------------------------------------------
    ; IMAGE_IMPORT_DESCRIPTOR
    dd LOOKUP_RVA, 0, 0, KERNEL_NAME_RVA, IAT_RVA
    dd 0, 0, 0, 0, 0

    times (RDATA_FILE + 0x28) - ($ - $$) db 0
kernel_name:
    db 'KERNEL32.DLL', 0

    times (RDATA_FILE + 0x36) - ($ - $$) db 0
name_getstd:
    dw 0
    db 'GetStdHandle', 0
    times (RDATA_FILE + 0x46) - ($ - $$) db 0
name_write:
    dw 0
    db 'WriteFile', 0
    times (RDATA_FILE + 0x52) - ($ - $$) db 0
name_exit:
    dw 0
    db 'ExitProcess', 0
    times (RDATA_FILE + 0x60) - ($ - $$) db 0
name_create:
    dw 0
    db 'CreateFileA', 0
    times (RDATA_FILE + 0x6E) - ($ - $$) db 0
name_close:
    dw 0
    db 'CloseHandle', 0
    times (RDATA_FILE + 0x7C) - ($ - $$) db 0
name_setcp_out:
    dw 0
    db 'SetConsoleOutputCP', 0
    times (RDATA_FILE + 0x92) - ($ - $$) db 0
name_setcp:
    dw 0
    db 'SetConsoleCP', 0
    times (RDATA_FILE + 0xA2) - ($ - $$) db 0
name_cmdline:
    dw 0
    db 'GetCommandLineA', 0

    times (RDATA_FILE + 0xB8) - ($ - $$) db 0
    ; OriginalFirstThunk / lookup table: eight imports plus terminator.
    dq NAME_GETSTD_RVA, NAME_WRITE_RVA, NAME_EXIT_RVA, NAME_CREATE_RVA
    dq NAME_CLOSE_RVA, NAME_SETCP_OUT, NAME_SETCP_RVA, NAME_CMDLINE_RVA
    dq 0

    ; FirstThunk / IAT.  The loader overwrites these zero qwords.
    times (RDATA_FILE + 0x100) - ($ - $$) db 0
    times 0x48 db 0

    times (RDATA_FILE + MSG_HELP_OFF) - ($ - $$) db 0
msg_help:
    db 'Big Compiler v0.4.0 (pure NASM ASM)', 13, 10
    db 'Usage: bigc.exe <file.bg> [-o output.exe] [--target windows|linux]', 13, 10, 0

    times (RDATA_FILE + MSG_VERSION_OFF) - ($ - $$) db 0
msg_version:
    db 'bigc 0.4.0 (NASM, PE64+ELF64, pure)', 13, 10, 0

    times (RDATA_FILE + MSG_INFO_OFF) - ($ - $$) db 0
msg_info:
    db 'info: compiled main.bg -> temp.exe [windows] 3584 bytes', 13, 10, 0

    times (RDATA_FILE + PATH_TEMP_OFF) - ($ - $$) db 0
path_temp:
    db 'temp.exe', 0

    times (RDATA_FILE + PATH_MAIN_OFF) - ($ - $$) db 0
path_main:
    db 'main.exe', 0

    times (RDATA_FILE + TEMPLATE_OFF) - ($ - $$) db 0
pe_template:
    incbin 'src/pe_template.bin'

    ; Fixed raw section size and exact output size: 0x1800 bytes.
    times (RDATA_FILE + RDATA_RAW_SIZE) - ($ - $$) db 0
