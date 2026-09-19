; =============================================================================
; Big Compiler v1.0.0 — настоящий компилятор языка Big, целиком на NASM.
;
;   nasm -f bin src\bigc.asm -o bigc.exe
;
; Читает исходник .bg, выполняет lex/parse/sema/codegen и собирает готовый
; автономный Windows x64 PE (.exe) без линкера, CRT и Python.
; Платформа назначения: ТОЛЬКО Windows 11 x64 (PE64), никаких других целей.
; =============================================================================

BITS 64
ORG 0

%define G_IMG           0x140000000

; ---- IAT компилятора (его собственная .rdata, RVA 0x1000) ----
%define COMP_IAT_BASE   (G_IMG + 0x1000)
%define COMP_GetCommandLineA   (COMP_IAT_BASE + 0x140)
%define COMP_CreateFileA       (COMP_IAT_BASE + 0x148)
%define COMP_ReadFile          (COMP_IAT_BASE + 0x150)
%define COMP_WriteFile         (COMP_IAT_BASE + 0x158)
%define COMP_GetStdHandle      (COMP_IAT_BASE + 0x160)
%define COMP_ExitProcess       (COMP_IAT_BASE + 0x168)
%define COMP_CloseHandle       (COMP_IAT_BASE + 0x170)
%define COMP_SetConsoleOutputCP (COMP_IAT_BASE + 0x178)
%define COMP_SetConsoleCP       (COMP_IAT_BASE + 0x180)
%define COMP_GetFileSizeEx     (COMP_IAT_BASE + 0x188)
%define COMP_VirtualAlloc      (COMP_IAT_BASE + 0x190)

; ---- IAT генерируемой программы (её .rdata, RVA 0x1000, блоб 0xE8 байт) ----
%define GEN_IAT_BASE   (G_IMG + 0x1000)
%define GEN_GetStdHandle       (GEN_IAT_BASE + 0xB8)
%define GEN_WriteFile          (GEN_IAT_BASE + 0xC0)
%define GEN_ExitProcess        (GEN_IAT_BASE + 0xC8)
%define GEN_SetConsoleOutputCP (GEN_IAT_BASE + 0xD0)
%define GEN_SetConsoleCP       (GEN_IAT_BASE + 0xD8)

; ---- смещения глобалов (база — куча компилятора, регистр rbx) ----
%define G_ARGC        0      ; dword
%define G_ARGV        8      ; 64 записи по 16 байт (ptr, len)
%define G_SRCPATH     1040
%define G_SRCPATHLEN  1048
%define G_SRC         1056   ; содержимое файла
%define G_SRCLEN      1064
%define G_TOK         1072
%define G_TOKCAP      1080
%define G_TOKCNT      1088
%define G_NODECUR     1096   ; арена AST-узлов
%define G_NODEEND     1104
%define G_HEAPCUR     1112   ; строки, таблицы, пути
%define G_HEAPEND     1120
%define G_CODE        1128   ; буфер машинного кода цели
%define G_CODECUR     1136
%define G_CODEEND     1144
%define G_RDATA       1152   ; буфер .rdata цели
%define G_RDATACUR    1160
%define G_RDATAEND    1168
%define G_OUT         1176   ; собираемый PE
%define G_OUTLEN      1184
%define G_OUTEND      1192
%define G_FUNC        1200   ; массив указателей на узлы функций
%define G_FUNCCNT     1208
%define G_ERRCNT      1216
%define G_LABELS      1224   ; массив смещений меток
%define G_LABELCNT    1232
%define G_FIXPOS      1240
%define G_FIXLAB      1248
%define G_FIXCNT      1256
%define G_OUTPATH 1264
%define G_OUTPATHLEN 1272
%define G_SIZE 1280

; ---- виды токенов ----
%define TOK_EOF        0
%define TOK_IDENT      1
%define TOK_INT        2
%define TOK_STRING     3
%define TOK_FUNC       4
%define TOK_LET        5
%define TOK_IF         6
%define TOK_ELSE       7
%define TOK_WHILE      8
%define TOK_FOR        9
%define TOK_IN         10
%define TOK_RETURN     11
%define TOK_TRUE       12
%define TOK_FALSE      13
%define TOK_LPAREN     14
%define TOK_RPAREN     15
%define TOK_LBRACE     16
%define TOK_RBRACE     17
%define TOK_COMMA      18
%define TOK_SEMI       19
%define TOK_COLON      20
%define TOK_ARROW      21
%define TOK_DOT2       22
%define TOK_LBRACKET   40
%define TOK_RBRACKET   41
%define TOK_PLUS       24
%define TOK_MINUS      25
%define TOK_STAR       26
%define TOK_SLASH      27
%define TOK_PERCENT    28
%define TOK_EQEQ       29
%define TOK_NEQ        30
%define TOK_LT         31
%define TOK_GT         32
%define TOK_LE         33
%define TOK_GE         34
%define TOK_AND        35
%define TOK_OR         36
%define TOK_NOT        37
%define TOK_ASSIGN     38
%define TOK_CONST      42
%define TOK_USE        43
%define TOK_IMPORT     44
%define TOK_BREAK      45
%define TOK_CONTINUE   46

; ---- виды AST-узлов ----
%define NODE_FUNC       2
%define NODE_BLOCK      3
%define NODE_LET        4
%define NODE_ASSIGN     5
%define NODE_IF         6
%define NODE_WHILE      7
%define NODE_FOR        8
%define NODE_RETURN     9
%define NODE_EXPRSTMT   10
%define NODE_EINT       11
%define NODE_ESTR       12
%define NODE_EBOOL      13
%define NODE_EIDENT     14
%define NODE_EBIN       15
%define NODE_EUN        16
%define NODE_ECALL      17
%define NODE_PARAM      18

; ---- операции ----
%define OP_ADD 1
%define OP_SUB 2
%define OP_MUL 3
%define OP_DIV 4
%define OP_MOD 5
%define OP_EQ  6
%define OP_NE  7
%define OP_LT  8
%define OP_GT  9
%define OP_LE  10
%define OP_GE  11
%define OP_AND 12
%define OP_OR  13
%define OP_NEG 20
%define OP_NOT 21

; ---- типы ----
%define TY_I32  1
%define TY_I64  2
%define TY_BOOL 3
%define TY_STR  4
%define TY_VOID 5

; ---- узел AST: 72 байта ----
%define N_KIND  0
%define N_A     8
%define N_B     16
%define N_C     24
%define N_D     32
%define N_E     40
%define N_F     48
%define N_G     56
%define N_NEXT  64

; ---- токен: 24 байта ----
%define TK_KIND 0     ; dword
%define TK_LINE 4     ; dword
%define TK_LEN  8     ; dword
%define TK_PTR  16    ; qword
%define TK_SIZE 24

; ---- метки генерируемого кода ----
%define LAB_ENTRY     0
%define LAB_PRINTSTR  1
%define LAB_PRINTINT  2
%define LAB_NEWLINE   3
%define LAB_FUNC_BASE 4      ; функция i -> метка 4+i
; смещение "\r\n" в .rdata цели (сразу после блоба импорта 0xE8)
%define GEN_NL_OFF    0xF0           ; фактическое смещение "\r\n" в блобе

; перевод файлового смещения (ассемблируется с ORG 0) в runtime VA
%define VA_RDATA(x)  (G_IMG + 0x1000 + ((x) - rdata_start))
%define VA_TEXT(x)   (G_IMG + TEXT_RVA + ((x) - text_start))

%define COMP_IAT_OFF 0x140

; вызов API компилятора через абсолютный адрес слота IAT
%macro API 1
    mov rax, %1
    mov rax, [rax]
    call rax
%endmacro

; =============================================================================
; Заголовок PE самого компилятора (патчится equs на 2-м проходе)
; =============================================================================
    db 'M', 'Z'
    times 0x3A db 0
    dd 0x80                         ; e_lfanew
    times 0x80 - ($ - $$) db 0

    db 'P', 'E', 0, 0
    dw 0x8664                       ; x86-64
    dw 2                            ; секции: .rdata, .text
    dd 0
    dd 0
    dd 0
    dw 240                          ; SizeOfOptionalHeader
    dw 0x0022

    dw 0x020B                       ; PE32+
    db 14, 0                        ; linker 14.0
    dd TEXT_RAW                     ; SizeOfCode
    dd RDATA_RAW                    ; SizeOfInitializedData
    dd 0
    dd TEXT_RVA                     ; AddressOfEntryPoint (entry в начале .text)
    dd TEXT_RVA                     ; BaseOfCode
    dq G_IMG
    dd 0x1000                       ; SectionAlignment
    dd 0x200                        ; FileAlignment
    dw 6, 0
    dw 0, 0
    dw 6, 0
    dd 0
    dd IMAGE_SIZE
    dd 0x200                        ; SizeOfHeaders
    dd 0
    dw 3                            ; subsystem: console
    dw 0                            ; DllCharacteristics: фикс. база, без ASLR
    dq 0x100000
    dq 0x1000
    dq 0x100000
    dq 0x1000
    dd 0
    dd 16                           ; NumberOfRvaAndSizes
    ; каталоги данных (16 штук)
    dd 0, 0                         ; export
    dd 0x1000, 40                   ; import
    times 20 dd 0                   ; resource..bound import
    dd 0x1000 + COMP_IAT_OFF, 11*8  ; IAT
    times 6 dd 0                    ; delay, CLR, reserved

    ; секция .rdata
    db '.rdata', 0, 0
    dd RDATA_VSIZE
    dd 0x1000
    dd RDATA_RAW
    dd 0x200
    dd 0, 0
    dw 0, 0
    dd 0x40000040
    ; секция .text
    db '.text', 0, 0, 0
    dd TEXT_VSIZE
    dd TEXT_RVA
    dd TEXT_RAW
    dd TEXT_FILEOFF
    dd 0, 0
    dw 0, 0
    dd 0x60000020

    times 0x200 - ($ - $$) db 0

; =============================================================================
; .rdata компилятора: таблица импорта (11 функций) + строки
; =============================================================================
rdata_start:
    db 0xe0, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0x10, 0x00, 0x00
    db 0x40, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4b, 0x45, 0x52, 0x4e, 0x45, 0x4c, 0x33, 0x32
    db 0x2e, 0x44, 0x4c, 0x4c, 0x00, 0x00, 0x00, 0x00, 0x47, 0x65, 0x74, 0x43, 0x6f, 0x6d, 0x6d, 0x61
    db 0x6e, 0x64, 0x4c, 0x69, 0x6e, 0x65, 0x41, 0x00, 0x00, 0x00, 0x43, 0x72, 0x65, 0x61, 0x74, 0x65
    db 0x46, 0x69, 0x6c, 0x65, 0x41, 0x00, 0x00, 0x00, 0x52, 0x65, 0x61, 0x64, 0x46, 0x69, 0x6c, 0x65
    db 0x00, 0x00, 0x00, 0x00, 0x57, 0x72, 0x69, 0x74, 0x65, 0x46, 0x69, 0x6c, 0x65, 0x00, 0x00, 0x00
    db 0x47, 0x65, 0x74, 0x53, 0x74, 0x64, 0x48, 0x61, 0x6e, 0x64, 0x6c, 0x65, 0x00, 0x00, 0x00, 0x00
    db 0x45, 0x78, 0x69, 0x74, 0x50, 0x72, 0x6f, 0x63, 0x65, 0x73, 0x73, 0x00, 0x00, 0x00, 0x43, 0x6c
    db 0x6f, 0x73, 0x65, 0x48, 0x61, 0x6e, 0x64, 0x6c, 0x65, 0x00, 0x00, 0x00, 0x53, 0x65, 0x74, 0x43
    db 0x6f, 0x6e, 0x73, 0x6f, 0x6c, 0x65, 0x4f, 0x75, 0x74, 0x70, 0x75, 0x74, 0x43, 0x50, 0x00, 0x00
    db 0x00, 0x00, 0x53, 0x65, 0x74, 0x43, 0x6f, 0x6e, 0x73, 0x6f, 0x6c, 0x65, 0x43, 0x50, 0x00, 0x00
    db 0x00, 0x00, 0x47, 0x65, 0x74, 0x46, 0x69, 0x6c, 0x65, 0x53, 0x69, 0x7a, 0x65, 0x45, 0x78, 0x00
    db 0x00, 0x00, 0x56, 0x69, 0x72, 0x74, 0x75, 0x61, 0x6c, 0x41, 0x6c, 0x6c, 0x6f, 0x63, 0x00, 0x00
    db 0x36, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x48, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x56, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x62, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x6e, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x8c, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9a, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xb0, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xd0, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x36, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x48, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x56, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x62, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x6e, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x8c, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9a, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xb0, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xd0, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

msg_help:
    db 'Big Compiler v1.0.0 (pure NASM, Windows 11 x64, PE64)', 13, 10
    db 'Usage: bigc.exe <file.bg> [-o output.exe] [--target windows]', 13, 10
    db 'Compiles Big source into a standalone Windows x64 .exe.', 13, 10, 0
msg_version:
    db 'bigc 1.0.0 (NASM, PE64, Windows-only)', 13, 10, 0
msg_error_prefix:
    db 'error: ', 0
msg_line_prefix:
    db ' (line ', 0
msg_paren_close:
    db ')', 0
msg_no_input:
    db 'no input file given (expected <file.bg>)', 0
msg_cant_open:
    db 'cannot open file: ', 0
msg_cant_write:
    db 'cannot write file: ', 0
msg_compiled:
    db 'compiled OK -> ', 0
msg_newline:
    db 13, 10, 0
msg_undef_var:
    db 'undefined variable: ', 0
msg_undef_func:
    db 'undefined function: ', 0
msg_redef:
    db 'redefinition of: ', 0
msg_arity:
    db 'wrong number of arguments for: ', 0
msg_intrinsic_arity:
    db 'print/println expects 0 or 1 argument', 0
msg_type_mismatch:
    db 'type mismatch in declaration of: ', 0
msg_no_main:
    db 'function main() not found', 0
msg_out_of_mem:
    db 'out of memory', 0
msg_main_name:
    db 'main', 0

rdata_end:

RDATA_VSIZE  equ (rdata_end - rdata_start)
RDATA_RAW    equ ((RDATA_VSIZE + 0x1FF) & ~0x1FF)
TEXT_FILEOFF equ (0x200 + RDATA_RAW)
TEXT_RVA     equ (0x1000 + ((RDATA_VSIZE + 0xFFF) & ~0xFFF))
TEXT_VSIZE   equ (text_end - text_start)
TEXT_RAW     equ ((TEXT_VSIZE + 0x1FF) & ~0x1FF)
IMAGE_SIZE   equ (TEXT_RVA + ((TEXT_VSIZE + 0xFFF) & ~0xFFF))

    times (TEXT_FILEOFF - ($ - $$)) db 0

; =============================================================================
; .text — компилятор
; =============================================================================
text_start:
entry:
    cld                              ; направление строк — вперёд (важно для всех rep)
    push rbx                        ; сохраняем базу глобалов (и выравнивание)
    sub rsp, 0x20
    mov ecx, 65001
    API COMP_SetConsoleOutputCP
    mov ecx, 65001
    API COMP_SetConsoleCP
    add rsp, 0x20

    ; куча компилятора: 8 МБ под глобалы/строки/таблицы
    xor ecx, ecx
    mov rdx, 8*1024*1024
    mov r8, 0x3000
    mov r9, 4
    API COMP_VirtualAlloc
    mov rbx, rax
    add rax, G_SIZE
    mov [rbx + G_HEAPCUR], rax
    mov rax, [rbx + G_HEAPCUR]
    mov rcx, 8*1024*1024
    add rax, rcx
    mov [rbx + G_HEAPEND], rax

    call init_globals
    call parse_args
    call handle_meta
    call read_input
    call lex
    call parse_program
    call sema
    ; если были ошибки — выход 1
    cmp qword [rbx + G_ERRCNT], 0
    je .codegen
    mov ecx, 1
    API COMP_ExitProcess
.codegen:
    call codegen
    call build_pe
    call write_output

    ; успех: "compiled OK -> <path>\r\n" в stdout
    mov ecx, -11
    API COMP_GetStdHandle
    mov r12, rax
    mov rdx, VA_RDATA(msg_compiled)
    mov r8, 15
    call comp_write
    mov rdx, [rbx + G_OUTPATH]
    mov r8, [rbx + G_OUTPATHLEN]
    call comp_write
    mov rdx, VA_RDATA(msg_newline)
    mov r8, 2
    call comp_write

    xor ecx, ecx
    API COMP_ExitProcess

; ---------------------------------------------------------------------------
; comp_write: r12=хендл, rdx=буфер, r8=длина (портит r9, r10, rax, rcx, rdx, r8)
; ---------------------------------------------------------------------------
comp_write:
    sub rsp, 0x30
    mov rcx, r12                    ; handle
    ; rdx = buf, r8 = len — заданы вызывающим
    lea r9, [rsp+0x28]              ; &written
    mov qword [rsp+0x28], 0
    mov qword [rsp+0x20], 0         ; lpOverlapped = NULL
    API COMP_WriteFile
    add rsp, 0x30
    ret

; comp_write_err: rdx=буфер, r8=длина — сама берёт stderr
comp_write_err:
    push rbx
    push r12
    mov ecx, -12
    API COMP_GetStdHandle
    mov r12, rax
    call comp_write
    pop r12
    pop rbx
    ret

; comp_print_int: печать числа в rax в stderr (для диагностик: номеров строк)
comp_print_int:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x50
    mov r13, rax                    ; значение
    mov ecx, -12
    API COMP_GetStdHandle
    mov r12, rax
    mov rax, r13
    xor r14d, r14d
    test rax, rax
    jns .p_pos
    neg rax
    mov r14d, 1
.p_pos:
    lea r10, [rsp+0x48]             ; буфер цифр (заполняем вниз)
    xor r11d, r11d
    mov r9, 10
.p_digit:
    xor rdx, rdx
    div r9
    add dl, '0'
    dec r10
    mov [r10], dl
    inc r11d
    test rax, rax
    jnz .p_digit
    test r14d, r14d
    jz .p_write
    dec r10
    mov byte [r10], '-'
    inc r11d
.p_write:
    mov rcx, r12
    mov rdx, r10
    mov r8, r11
    mov qword [rsp+0x20], 0         ; lpOverlapped
    mov qword [rsp+0x28], 0         ; written
    lea r9, [rsp+0x28]
    API COMP_WriteFile
    add rsp, 0x50
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

fatal_err:
    push rbx
    push r12
    mov ecx, -12
    API COMP_GetStdHandle
    mov r12, rax
    call comp_write
    mov rdx, VA_RDATA(msg_newline)
    mov r8, 2
    call comp_write
    mov ecx, 1
    API COMP_ExitProcess

; ---------------------------------------------------------------------------
; heap_alloc: rcx = размер -> rax = блок в куче (выравнивание 8)
; ---------------------------------------------------------------------------
heap_alloc:
    push rdx
    mov rdx, [rbx + G_HEAPCUR]
    lea rax, [rdx + rcx + 7]
    and rax, ~7
    cmp rax, [rbx + G_HEAPEND]
    jg .oom
    mov [rbx + G_HEAPCUR], rax
    mov rax, rdx
    pop rdx
    ret
.oom:
    mov rdx, VA_RDATA(msg_out_of_mem)
    mov r8, 13
    call fatal_err

; ---------------------------------------------------------------------------
; valloc: rcx = размер -> rax = свежая страница/регион (VirtualAlloc)
; ---------------------------------------------------------------------------
valloc:
    mov rdx, rcx                     ; dwSize
    xor ecx, ecx                     ; lpAddress = NULL
    mov r8, 0x3000                   ; MEM_COMMIT | MEM_RESERVE
    mov r9, 4                        ; PAGE_READWRITE
    API COMP_VirtualAlloc
    test rax, rax
    jnz .vl_ok
    mov rdx, VA_RDATA(msg_out_of_mem)
    mov r8, 13
    call fatal_err
.vl_ok:
    ret

; ---------------------------------------------------------------------------
; node_alloc: rax = новый узел AST (64 байта, обнулён)
; ---------------------------------------------------------------------------
node_alloc:
    push rcx
    push rdi
    mov rax, [rbx + G_NODECUR]
    lea rcx, [rax + 72]
    cmp rcx, [rbx + G_NODEEND]
    jg .oom
    mov [rbx + G_NODECUR], rcx
    mov rdi, rax
    ; обнуление 72 байт явным циклом (не зависит от флага направления)
    xor eax, eax
    mov ecx, 9
.na_zero:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .na_zero
    sub rdi, 72
    mov rax, rdi
    pop rdi
    pop rcx
    ret
.oom:
    mov rdx, VA_RDATA(msg_out_of_mem)
    mov r8, 13
    call fatal_err

; ---------------------------------------------------------------------------
; init_globals: буферы токенов, узлов, кода, .rdata, выхода; блоб импорта цели
; ---------------------------------------------------------------------------
init_globals:
    push rbx
    ; токены: 2 МБ
    mov rcx, 2*1024*1024
    call valloc
    mov [rbx + G_TOK], rax
    mov qword [rbx + G_TOKCAP], (2*1024*1024) / TK_SIZE
    mov qword [rbx + G_TOKCNT], 0
    ; узлы: 16 МБ
    mov rcx, 16*1024*1024
    call valloc
    mov [rbx + G_NODECUR], rax
    add rax, 16*1024*1024
    mov [rbx + G_NODEEND], rax
    ; код цели: 8 МБ
    mov rcx, 8*1024*1024
    call valloc
    mov [rbx + G_CODE], rax
    mov [rbx + G_CODECUR], rax
    add rax, 8*1024*1024
    mov [rbx + G_CODEEND], rax
    ; .rdata цели: 1 МБ, сразу кладём блоб импорта (0xE8) и "\r\n"
    mov rcx, 1024*1024
    call valloc
    mov [rbx + G_RDATA], rax
    mov [rbx + G_RDATACUR], rax
    add rax, 1024*1024
    mov [rbx + G_RDATAEND], rax
    push rsi
    push rdi
    mov rsi, VA_TEXT(gen_import_blob)
    mov rdi, [rbx + G_RDATA]
    mov ecx, gen_blob_len
.ig_cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz .ig_cp
    add qword [rbx + G_RDATACUR], gen_blob_len
    pop rdi
    pop rsi
    ; выходной буфер: 16 МБ
    mov rcx, 16*1024*1024
    call valloc
    mov [rbx + G_OUT], rax
    mov qword [rbx + G_OUTLEN], 0
    add rax, 16*1024*1024
    mov [rbx + G_OUTEND], rax
    ; массив функций: 1024 указателя
    mov rcx, 1024*8
    call valloc
    mov [rbx + G_FUNC], rax
    mov qword [rbx + G_FUNCCNT], 0
    ; метки и фиксапы: по 8192 записей
    mov rcx, 8192*8
    call valloc
    mov [rbx + G_LABELS], rax
    mov rcx, 8192*8
    call valloc
    mov [rbx + G_FIXPOS], rax
    mov rcx, 8192*8
    call valloc
    mov [rbx + G_FIXLAB], rax
    mov qword [rbx + G_LABELCNT], 0
    mov qword [rbx + G_FIXCNT], 0
    mov qword [rbx + G_ERRCNT], 0
    pop rbx
    ret

; ---------------------------------------------------------------------------
; parse_args: GetCommandLineA -> argv[64] = {ptr,len}
; ---------------------------------------------------------------------------
parse_args:
    push rbx
    push rsi
    push rdi
    push r12
    API COMP_GetCommandLineA
    mov rsi, rax
    xor r12, r12                    ; argc
    lea rdi, [rbx + G_ARGV]
.pa_loop:
.pa_skip:
    mov al, [rsi]
    cmp al, ' '
    je .pa_adv
    cmp al, 9
    je .pa_adv
    test al, al
    jz .pa_done
    jmp .pa_start
.pa_adv:
    inc rsi
    jmp .pa_skip
.pa_start:
    cmp byte [rsi], '"'
    jne .pa_plain
    inc rsi
    mov [rdi], rsi
    xor ecx, ecx
.pa_q:
    mov al, [rsi]
    cmp al, '"'
    je .pa_qend
    test al, al
    jz .pa_qend
    inc rsi
    inc ecx
    jmp .pa_q
.pa_qend:
    mov [rdi+8], ecx
    cmp byte [rsi], '"'
    jne .pa_store
    inc rsi
    jmp .pa_store
.pa_plain:
    mov [rdi], rsi
    xor ecx, ecx
.pa_p:
    mov al, [rsi]
    cmp al, ' '
    je .pa_pend
    cmp al, 9
    je .pa_pend
    test al, al
    jz .pa_pend
    inc rsi
    inc ecx
    jmp .pa_p
.pa_pend:
    mov [rdi+8], ecx
.pa_store:
    ; копируем аргумент в кучу с NUL-терминатором
    push rsi
    push rdi
    push r12
    mov rsi, [rdi]             ; исходный ptr
    mov rcx, [rdi+8]           ; длина
    inc rcx
    push rcx
    call heap_alloc
    pop rcx
    pop r12
    mov rdi, rax               ; назначение
    mov rdx, rax
    dec rcx
    test rcx, rcx
    jz .pa_cpd
.pa_cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .pa_cp
.pa_cpd:
    mov byte [rdi], 0
    pop rdi                    ; запись argv
    mov [rdi], rdx             ; новый ptr из кучи
    pop rsi
    add rdi, 16
    inc r12
    cmp r12, 64
    jge .pa_done
    jmp .pa_loop
.pa_done:
    mov [rbx + G_ARGC], r12d
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; handle_meta: --help/--version/-o <path>/--target X; входной файл
; ---------------------------------------------------------------------------
handle_meta:
    push rbx
    push rsi
    push rdi
    push r12
    mov r12d, [rbx + G_ARGC]
    mov esi, 1                     ; argv[0] — имя программы
.hm_next:
    cmp esi, r12d
    jge .hm_done
    lea rdi, [rbx + G_ARGV]
    mov eax, esi
    shl rax, 4
    add rdi, rax
    mov rcx, [rdi]                  ; ptr
    mov r8, [rdi+8]                 ; len
    cmp r8, 6
    jne .hm_ver
    ; сравниваем "--help" посимвольно
    cmp byte [rcx], '-'
    jne .hm_ver
    cmp byte [rcx+1], '-'
    jne .hm_ver
    cmp byte [rcx+2], 'h'
    jne .hm_ver
    cmp byte [rcx+3], 'e'
    jne .hm_ver
    cmp byte [rcx+4], 'l'
    jne .hm_ver
    cmp byte [rcx+5], 'p'
    jne .hm_ver
    mov ecx, -11
    API COMP_GetStdHandle
    mov r12, rax
    mov rdx, VA_RDATA(msg_help)
    mov r8, 174
    call comp_write
    xor ecx, ecx
    API COMP_ExitProcess
.hm_ver:
    cmp r8, 9
    jne .hm_opts
    cmp byte [rcx], '-'
    jne .hm_opts
    cmp byte [rcx+1], '-'
    jne .hm_opts
    cmp byte [rcx+2], 'v'
    jne .hm_opts
    cmp byte [rcx+3], 'e'
    jne .hm_opts
    cmp byte [rcx+4], 'r'
    jne .hm_opts
    cmp byte [rcx+5], 's'
    jne .hm_opts
    cmp byte [rcx+6], 'i'
    jne .hm_opts
    cmp byte [rcx+7], 'o'
    jne .hm_opts
    cmp byte [rcx+8], 'n'
    jne .hm_opts
    mov ecx, -11
    API COMP_GetStdHandle
    mov r12, rax
    mov rdx, VA_RDATA(msg_version)
    mov r8, 39
    call comp_write
    xor ecx, ecx
    API COMP_ExitProcess
.hm_opts:
    cmp byte [rcx], '-'
    je .hm_dash
    ; входной файл (первый без '-')
    cmp qword [rbx + G_SRCPATH], 0
    jne .hm_cont
    mov [rbx + G_SRCPATH], rcx
    mov [rbx + G_SRCPATHLEN], r8
    jmp .hm_cont
.hm_dash:
    ; -o <out>
    cmp r8, 2
    jne .hm_target
    cmp byte [rcx+1], 'o'
    jne .hm_target
    inc esi
    cmp esi, r12d
    jge .hm_cont
    mov eax, esi
    shl rax, 4
    lea rdi, [rbx + G_ARGV]
    add rdi, rax
    mov rcx, [rdi]
    mov r8, [rdi+8]
    mov [rbx + G_OUTPATH], rcx
    mov [rbx + G_OUTPATHLEN], r8
    jmp .hm_cont
.hm_target:
    ; --target windows|--target <x>: единственная цель — Windows, принимаем молча
    cmp r8, 8
    jne .hm_cont
    cmp byte [rcx+1], 't'
    jne .hm_cont
    inc esi                          ; проглотить значение
.hm_cont:
    inc esi
    jmp .hm_next
.hm_done:
    cmp qword [rbx + G_SRCPATH], 0
    jne .hm_ok
    mov rdx, VA_RDATA(msg_no_input)
    mov r8, 40
    call fatal_err
.hm_ok:
    cmp qword [rbx + G_OUTPATH], 0
    jne .hm_outset
    call derive_output
.hm_outset:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; derive_output: <input>.bg -> <input>.exe (в куче)
; ---------------------------------------------------------------------------
derive_output:
    push rbx
    push rsi
    push rdi
    push rcx
    mov rsi, [rbx + G_SRCPATH]
    mov rcx, [rbx + G_SRCPATHLEN]
    ; ищем последнюю '.' после последнего '/' или '\'
    lea rax, [rsi + rcx]
    mov rdi, rsi
    add rdi, rcx                    ; default: конец имени
.find:
    cmp rax, rsi
    jle .found
    dec rax
    cmp byte [rax], '.'
    je .dot
    cmp byte [rax], '/'
    je .found_keep
    cmp byte [rax], '\'
    jne .find
.found_keep:
    jmp .found
.dot:
    lea rdi, [rax]
    jmp .found
.found:
    ; выделить (rdi-rsi)+5
    mov rcx, rdi
    sub rcx, rsi
    add rcx, 5
    push rdi
    push rsi
    push rcx
    call heap_alloc
    pop rcx
    pop rsi
    pop rdi
    mov [rbx + G_OUTPATH], rax
    mov [rbx + G_OUTPATHLEN], rdi
    sub qword [rbx + G_OUTPATHLEN], rsi
    add qword [rbx + G_OUTPATHLEN], 4
    mov rdi, rax
    sub rcx, 5                      ; длина основы
.op_cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .op_cp
    mov byte [rdi], '.'
    mov byte [rdi+1], 'e'
    mov byte [rdi+2], 'x'
    mov byte [rdi+3], 'e'
    mov byte [rdi+4], 0
    pop rcx
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; read_input: читаем исходник целиком в кучу
; ---------------------------------------------------------------------------
read_input:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x40
    mov rcx, [rbx + G_SRCPATH]
    mov rdx, 0x80000000             ; GENERIC_READ
    mov r8, 1                       ; FILE_SHARE_READ
    xor r9, r9
    mov qword [rsp+0x20], 3         ; OPEN_EXISTING
    mov qword [rsp+0x28], 0x80      ; FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+0x30], 0
    API COMP_CreateFileA
    cmp rax, -1
    je .fail
    mov r12, rax
    mov rcx, r12                    ; дескриптор файла
    lea rdx, [rbx + G_SRCLEN]
    mov qword [rbx + G_SRCLEN], 0
    API COMP_GetFileSizeEx
    mov rsi, [rbx + G_SRCLEN]
    mov rcx, rsi
    inc rcx
    call heap_alloc
    mov r15, rax
    mov [rbx + G_SRC], rax
    xor r13, r13                    ; прочитано
.ri_loop:
    mov rcx, r12
    lea rdx, [r15 + r13]
    mov r8, 0x40000
    lea r9, [rsp+0x28]
    mov qword [rsp+0x20], 0
    mov qword [rsp+0x28], 0
    API COMP_ReadFile
    test rax, rax
    jz .ri_done
    mov ecx, [rsp+0x28]
    test ecx, ecx
    jz .ri_done
    add r13, rcx
    cmp r13, rsi
    jge .ri_done
    jmp .ri_loop
.ri_done:
    mov [rbx + G_SRCLEN], r13
    mov byte [r15 + r13], 0
    mov rcx, r12
    API COMP_CloseHandle
    add rsp, 0x40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
.fail:
    mov ecx, -12
    API COMP_GetStdHandle
    mov r12, rax
    mov rdx, VA_RDATA(msg_cant_open)
    mov r8, 18
    call comp_write
    mov rdx, [rbx + G_SRCPATH]
    mov r8, [rbx + G_SRCPATHLEN]
    call comp_write
    mov rdx, VA_RDATA(msg_newline)
    mov r8, 2
    call comp_write
    mov ecx, 1
    API COMP_ExitProcess

; =============================================================================
; ЛЕКСЕР
; =============================================================================

; emit_token: ecx=kind, r8=ptr/значение, r9d=len; строка — в [rbx+G_TOKCNT]
emit_token:
    push rbx
    push rax
    push rdx
    push r10
    mov rax, [rbx + G_TOKCNT]
    cmp rax, [rbx + G_TOKCAP]
    jge .et_full
    mov r10, [rbx + G_TOK]
    imul rdx, rax, TK_SIZE
    add r10, rdx
    mov [r10 + TK_KIND], ecx
    mov [r10 + TK_LINE], r12d
    mov [r10 + TK_LEN], r9d
    mov [r10 + TK_PTR], r8
    inc qword [rbx + G_TOKCNT]
.et_full:
    pop r10
    pop rdx
    pop rax
    pop rbx
    ret

; classify_kw: r9=ptr, rdx=len -> ecx=kind (или TOK_IDENT)
classify_kw:
    cmp rdx, 2
    je .ck2
    cmp rdx, 3
    je .ck3
    cmp rdx, 4
    je .ck4
    cmp rdx, 5
    je .ck5
    cmp rdx, 6
    je .ck6
    cmp rdx, 8
    je .ck8
    jmp .ck_ident
.ck2:
    cmp byte [r9], 'f'
    jne .ck2b
    cmp byte [r9+1], 'n'
    jne .ck_ident
    mov ecx, TOK_FUNC
    ret
.ck2b:
    cmp byte [r9], 'i'
    jne .ck_ident
    cmp byte [r9+1], 'n'
    je .ck_in
    cmp byte [r9+1], 'f'
    je .ck_if
    jmp .ck_ident
.ck_in:  mov ecx, TOK_IN
    ret
.ck_if:  mov ecx, TOK_IF
    ret
.ck3:
    cmp byte [r9], 'l'
    jne .ck3b
    cmp word [r9+1], 'et'
    jne .ck_ident
    mov ecx, TOK_LET
    ret
.ck3b:
    cmp byte [r9], 'v'
    jne .ck3c
    cmp word [r9+1], 'ar'
    jne .ck_ident
    mov ecx, TOK_LET
    ret
.ck3c:
    cmp byte [r9], 'f'
    jne .ck3d
    cmp word [r9+1], 'o' | ('r' << 8)   ; память "or": младший байт — 'o'
    jne .ck_ident
    mov ecx, TOK_FOR
    ret
.ck3d:
    cmp byte [r9], 'u'
    jne .ck_ident
    cmp word [r9+1], 's' | ('e' << 8)   ; память "se": младший байт — 's'
    jne .ck_ident
    mov ecx, TOK_USE
    ret
.ck4:
    cmp dword [r9], 'func'
    je .ck_func
    cmp dword [r9], 'else'
    je .ck_else
    cmp dword [r9], 'true'
    je .ck_true
    jmp .ck_ident
.ck_func: mov ecx, TOK_FUNC
    ret
.ck_else: mov ecx, TOK_ELSE
    ret
.ck_true: mov ecx, TOK_TRUE
    ret
.ck5:
    cmp dword [r9], 'whil'
    je .ck_while
    cmp dword [r9], 'cons'
    je .ck_const
    cmp dword [r9], 'brea'
    je .ck_break
    cmp dword [r9], 'fals'
    je .ck_false
    jmp .ck_ident
.ck_while:
    cmp byte [r9+4], 'e'
    jne .ck_ident
    mov ecx, TOK_WHILE
    ret
.ck_const:
    cmp byte [r9+4], 't'
    jne .ck_ident
    mov ecx, TOK_CONST
    ret
.ck_break:
    cmp byte [r9+4], 'k'
    jne .ck_ident
    mov ecx, TOK_BREAK
    ret
.ck_false:
    cmp byte [r9+4], 'e'
    jne .ck_ident
    mov ecx, TOK_FALSE
    ret
.ck6:
    cmp dword [r9], 'retu'
    je .ck_return
    cmp dword [r9], 'impo'
    je .ck_import
    jmp .ck_ident
.ck_return:
    cmp byte [r9+4], 'r'
    jne .ck_ident
    cmp byte [r9+5], 'n'
    jne .ck_ident
    mov ecx, TOK_RETURN
    ret
.ck_import:
    cmp byte [r9+4], 'r'
    jne .ck_ident
    cmp byte [r9+5], 't'
    jne .ck_ident
    mov ecx, TOK_IMPORT
    ret
.ck8:
    cmp dword [r9], 'cont'
    jne .ck_ident
    cmp dword [r9+4], 'inue'
    jne .ck_ident
    mov ecx, TOK_CONTINUE
    ret
.ck_ident:
    mov ecx, TOK_IDENT
    ret

; ---------------------------------------------------------------------------
; lex: [rbx+G_SRC] -> поток токенов. Портит локальные регистры.
; ---------------------------------------------------------------------------
lex:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    mov rsi, [rbx + G_SRC]
    mov r13, rsi
    add r13, [rbx + G_SRCLEN]
    mov r12d, 1                     ; строка
.l_loop:
    cmp rsi, r13
    jge .l_eof
    mov al, [rsi]
    cmp al, ' '
    je .l_ws
    cmp al, 9
    je .l_ws
    cmp al, 13
    je .l_cr
    cmp al, 10
    je .l_lf
    cmp al, '/'
    jne .l_notcmt
    cmp byte [rsi+1], '/'
    je .l_linecmt
    cmp byte [rsi+1], '*'
    je .l_blockcmt
    jmp .l_punct
.l_notcmt:
    call is_ident_start
    test al, al
    jnz .l_ident
    mov al, [rsi]
    cmp al, '0'
    jl .l_notnum
    cmp al, '9'
    jg .l_notnum
    jmp .l_number
.l_notnum:
    cmp al, '"'
    je .l_string
    jmp .l_punct
.l_ws:
    inc rsi
    jmp .l_loop
.l_cr:
    inc rsi
    jmp .l_loop
.l_lf:
    inc rsi
    inc r12d
    jmp .l_loop
.l_linecmt:
    add rsi, 2
.l_lc:
    cmp rsi, r13
    jge .l_eof
    mov al, [rsi]
    cmp al, 10
    je .l_lf
    inc rsi
    jmp .l_lc
.l_blockcmt:
    add rsi, 2
.l_bc:
    cmp rsi, r13
    jge .l_eof
    mov al, [rsi]
    cmp al, 10
    jne .l_bc2
    inc r12d
.l_bc2:
    cmp al, '*'
    jne .l_bc3
    cmp byte [rsi+1], '/'
    je .l_bcend
.l_bc3:
    inc rsi
    jmp .l_bc
.l_bcend:
    add rsi, 2
    jmp .l_loop
.l_ident:
    mov r9, rsi
.l_id:
    inc rsi
    cmp rsi, r13
    jge .l_idend
    mov al, [rsi]
    call is_ident_char
    test al, al
    jnz .l_id
.l_idend:
    mov rdx, rsi
    sub rdx, r9
    call classify_kw
    ; ecx = вид
    mov r8, r9
    mov r9d, edx
    call emit_token
    jmp .l_loop
.l_number:
    xor r8d, r8d
.l_num:
    mov al, [rsi]
    sub al, '0'
    movzx eax, al
    imul r8d, r8d, 10
    add r8d, eax
    inc rsi
    cmp rsi, r13
    jge .l_numend
    mov al, [rsi]
    cmp al, '0'
    jl .l_numend
    cmp al, '9'
    jg .l_numend
    jmp .l_num
.l_numend:
    mov ecx, TOK_INT
    mov r9d, 0
    call emit_token                 ; r8 = значение
    jmp .l_loop
.l_string:
    inc rsi                          ; открывающая кавычка
    push rsi                         ; сохранить начало сырья
    xor r10, r10                     ; декодированная длина
.l_s1:
    cmp rsi, r13
    jge .l_s1end
    mov al, [rsi]
    cmp al, '"'
    je .l_s1end
    cmp al, '\'
    jne .l_s1c
    inc rsi
    cmp rsi, r13
    jge .l_s1end
    inc rsi
    inc r10
    jmp .l_s1
.l_s1c:
    cmp al, 10
    jne .l_s1b
    inc r12d
.l_s1b:
    inc rsi
    inc r10
    jmp .l_s1
.l_s1end:
    lea rcx, [r10 + 1]
    call heap_alloc
    mov r15, rax                     ; курсор записи
    mov r14, rax                     ; начало декодированной строки
    pop rsi                          ; начало сырья
.l_s2:
    cmp rsi, r13
    jge .l_s2end
    mov al, [rsi]
    cmp al, '"'
    je .l_s2end
    cmp al, '\'
    jne .l_s2c
    inc rsi
    mov al, [rsi]
    cmp al, 'n'
    je .l_esc_n
    cmp al, 't'
    je .l_esc_t
    cmp al, 'r'
    je .l_esc_r
    cmp al, '0'
    je .l_esc_0
    ; \" \\ и неизвестные — байт как есть
    jmp .l_s2put
.l_esc_n:
    mov al, 10
    jmp .l_s2put
.l_esc_t:
    mov al, 9
    jmp .l_s2put
.l_esc_r:
    mov al, 13
    jmp .l_s2put
.l_esc_0:
    xor al, al
    jmp .l_s2put
.l_s2c:
    cmp al, 10
    jne .l_s2put
    inc r12d
.l_s2put:
    mov [r15], al
    inc r15
    inc rsi
    jmp .l_s2
.l_s2end:
    cmp rsi, r13
    jge .l_s2noq
    inc rsi                          ; закрывающая кавычка
.l_s2noq:
    mov ecx, TOK_STRING
    mov r8, r14
    mov r9d, r10d
    call emit_token
    jmp .l_loop
.l_punct:
    call lex_punct
    jmp .l_loop
.l_eof:
    xor ecx, ecx                    ; TOK_EOF
    xor r8d, r8d
    xor r9d, r9d
    call emit_token
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; is_ident_start / is_ident_char: al (символ) -> al=1/0
is_ident_start:
    cmp al, '_'
    je .iis_y
    cmp al, 'a'
    jl .iis_n
    cmp al, 'z'
    jle .iis_y
    cmp al, 'A'
    jl .iis_n
    cmp al, 'Z'
    jle .iis_y
.iis_n:
    xor al, al
    ret
.iis_y:
    mov al, 1
    ret

is_ident_char:
    cmp al, '_'
    je .iic_y
    cmp al, 'a'
    jl .iic_a
    cmp al, 'z'
    jle .iic_y
.iic_a:
    cmp al, 'A'
    jl .iic_b
    cmp al, 'Z'
    jle .iic_y
.iic_b:
    cmp al, '0'
    jl .iic_n
    cmp al, '9'
    jle .iic_y
.iic_n:
    xor al, al
    ret
.iic_y:
    mov al, 1
    ret

; ---------------------------------------------------------------------------
; lex_punct: один символ (или два) пунктуации из [rsi]; двигает rsi
; ---------------------------------------------------------------------------
lex_punct:
    push rbx
    mov al, [rsi]
    cmp al, '('
    je .p1c
    cmp al, ')'
    je .p1d
    cmp al, '{'
    je .p1e
    cmp al, '}'
    je .p1f
    cmp al, ','
    je .p1g
    cmp al, ';'
    je .p1h
    cmp al, '+'
    je .p1i
    cmp al, '*'
    je .p1j
    cmp al, '%'
    je .p1k
    cmp al, '/'
    je .p1n
    cmp al, '['
    je .p1l
    cmp al, ']'
    je .p1m
    cmp al, '='
    je .p_eq
    cmp al, ':'
    je .p_colon
    cmp al, '.'
    je .p_dot
    cmp al, '-'
    je .p_minus
    cmp al, '<'
    je .p_lt
    cmp al, '>'
    je .p_gt
    cmp al, '!'
    je .p_not
    cmp al, '&'
    je .p_and
    cmp al, '|'
    je .p_or
    ; неизвестный символ — пропускаем
    inc rsi
    jmp .p_done
.p1c:  mov ecx, TOK_LPAREN
    jmp .p_emit1
.p1d:  mov ecx, TOK_RPAREN
    jmp .p_emit1
.p1e:  mov ecx, TOK_LBRACE
    jmp .p_emit1
.p1f:  mov ecx, TOK_RBRACE
    jmp .p_emit1
.p1g:  mov ecx, TOK_COMMA
    jmp .p_emit1
.p1h:  mov ecx, TOK_SEMI
    jmp .p_emit1
.p1i:  mov ecx, TOK_PLUS
    jmp .p_emit1
.p1j:  mov ecx, TOK_STAR
    jmp .p_emit1
.p1k:  mov ecx, TOK_PERCENT
    jmp .p_emit1
.p1n:  mov ecx, TOK_SLASH
    jmp .p_emit1
.p1l:  mov ecx, TOK_LBRACKET
    jmp .p_emit1
.p1m:  mov ecx, TOK_RBRACKET
    jmp .p_emit1
.p_eq:
    cmp byte [rsi+1], '='
    jne .p1
    mov ecx, TOK_EQEQ
    jmp .p_emit2
.p1:   mov ecx, TOK_ASSIGN
    jmp .p_emit1
.p_colon:
    cmp byte [rsi+1], ':'
    je .p_skip2                    ; '::' не используется
    mov ecx, TOK_COLON
    jmp .p_emit1
.p_dot:
    cmp byte [rsi+1], '.'
    jne .p_skip1                   ; одиночная '.' не используется
    mov ecx, TOK_DOT2
    jmp .p_emit2
.p_minus:
    cmp byte [rsi+1], '>'
    jne .p2
    mov ecx, TOK_ARROW
    jmp .p_emit2
.p2:   mov ecx, TOK_MINUS
    jmp .p_emit1
.p_lt:
    cmp byte [rsi+1], '='
    jne .p3
    mov ecx, TOK_LE
    jmp .p_emit2
.p3:   mov ecx, TOK_LT
    jmp .p_emit1
.p_gt:
    cmp byte [rsi+1], '='
    jne .p4
    mov ecx, TOK_GE
    jmp .p_emit2
.p4:   mov ecx, TOK_GT
    jmp .p_emit1
.p_not:
    cmp byte [rsi+1], '='
    jne .p5
    mov ecx, TOK_NEQ
    jmp .p_emit2
.p5:   mov ecx, TOK_NOT
    jmp .p_emit1
.p_and:
    cmp byte [rsi+1], '&'
    jne .p6
    inc rsi
.p6:   mov ecx, TOK_AND
    jmp .p_emit1
.p_or:
    cmp byte [rsi+1], '|'
    jne .p7
    inc rsi
.p7:   mov ecx, TOK_OR
    jmp .p_emit1
.p_skip1:
    inc rsi
    jmp .p_done
.p_skip2:
    add rsi, 2
    jmp .p_done
.p_emit1:
    xor r8d, r8d
    xor r9d, r9d
    call emit_token
    inc rsi
    jmp .p_done
.p_emit2:
    xor r8d, r8d
    xor r9d, r9d
    call emit_token
    add rsi, 2
    jmp .p_done
.p_done:
    pop rbx
    ret

; =============================================================================
; ПАРСЕР (позиция тока — r12; парсерные функции НЕ сохраняют r12)
; =============================================================================

; peek: eax = kind токена №r12 (EOF за пределами)
peek:
    push rbx
    push rsi
    mov rax, r12
    cmp rax, [rbx + G_TOKCNT]
    jge .pk_eof
    mov rsi, [rbx + G_TOK]
    imul rax, r12, TK_SIZE
    add rsi, rax
    mov eax, [rsi + TK_KIND]
    pop rsi
    pop rbx
    ret
.pk_eof:
    xor eax, eax
    pop rsi
    pop rbx
    ret

; peek_at: rax = индекс -> eax = kind
peek_at:
    push rbx
    push rsi
    cmp rax, [rbx + G_TOKCNT]
    jge .pa_eof
    mov rsi, [rbx + G_TOK]
    imul rax, rax, TK_SIZE
    add rsi, rax
    mov eax, [rsi + TK_KIND]
    pop rsi
    pop rbx
    ret
.pa_eof:
    xor eax, eax
    pop rsi
    pop rbx
    ret

; cur_tok: r8 = ptr, r9d = len текущего токена
cur_tok:
    push rbx
    push rsi
    push rax
    mov rsi, [rbx + G_TOK]
    imul rax, r12, TK_SIZE
    add rsi, rax
    mov r8, [rsi + TK_PTR]
    mov r9d, [rsi + TK_LEN]
    pop rax
    pop rsi
    pop rbx
    ret

; cur_line: eax = строка текущего токена
cur_line:
    push rbx
    push rsi
    push rcx
    mov rsi, [rbx + G_TOK]
    imul rcx, r12, TK_SIZE
    add rsi, rcx
    mov eax, [rsi + TK_LINE]
    pop rcx
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_program:
    push rbx
.prg_loop:
    call peek
    cmp eax, TOK_EOF
    je .prg_done
    cmp eax, TOK_FUNC
    je .prg_func
    cmp eax, TOK_USE
    je .prg_use
    cmp eax, TOK_IMPORT
    je .prg_use
    cmp eax, TOK_CONST
    je .prg_skipdecl
    cmp eax, TOK_SEMI
    je .prg_semi
    ; неизвестное на верхнем уровне — пропускаем токен
    inc r12
    jmp .prg_loop
.prg_semi:
    inc r12
    jmp .prg_loop
.prg_use:
    inc r12
    call peek
    cmp eax, TOK_STRING
    jne .prg_loop
    inc r12
    call peek
    cmp eax, TOK_SEMI
    jne .prg_loop
    inc r12
    jmp .prg_loop
.prg_skipdecl:
    ; const на верхнем уровне: потребляем до ';' / '}' / EOF
    inc r12
    call peek
    cmp eax, TOK_SEMI
    je .prg_skipsemi
    cmp eax, TOK_EOF
    je .prg_loop
    cmp eax, TOK_FUNC
    je .prg_loop
    inc r12
    jmp .prg_skipdecl
.prg_skipsemi:
    inc r12
    jmp .prg_loop
.prg_func:
    call parse_func_decl
    jmp .prg_loop
.prg_done:
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_func_decl:
    push rbx
    push rsi
    push r13
    push r14
    push r15
    inc r12                          ; 'func'
    call peek
    cmp eax, TOK_IDENT
    jne .pfd_err
    call cur_tok                     ; r8=имя, r9d=длина
    mov r13, r8
    mov r14d, r9d
    inc r12
    call node_alloc
    mov r15, rax
    mov qword [r15 + N_KIND], NODE_FUNC
    mov [r15 + N_A], r13
    mov [r15 + N_B], r14
    call peek
    cmp eax, TOK_LPAREN
    jne .pfd_err
    inc r12
    call parse_params                ; rax=голова параметров, rcx=количество
    mov [r15 + N_C], rax
    mov [r15 + N_D], rcx             ; nparams в младшем двойном слове
    call peek
    cmp eax, TOK_ARROW
    jne .pfd_noret
    inc r12
    call parse_type                  ; eax = тип возврата
    shl rax, 32
    or [r15 + N_D], rax
    jmp .pfd_body
.pfd_noret:
    mov rax, TY_I32
    shl rax, 32
    or [r15 + N_D], rax
.pfd_body:
    call peek
    cmp eax, TOK_LBRACE
    jne .pfd_err2
    call parse_block
    mov [r15 + N_E], rax
    mov rsi, [rbx + G_FUNC]
    mov rcx, [rbx + G_FUNCCNT]
    cmp rcx, 1024
    jge .pfd_reg_done
    mov [rsi + rcx*8], r15
    inc qword [rbx + G_FUNCCNT]
.pfd_reg_done:
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pfd_err:
    inc r12
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pfd_err2:
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret

; parse_params: -> rax = голова цепочки NODE_PARAM, rcx = количество
parse_params:
    push rbx
    push rsi
    push rdi
    push r13
    push r14
    xor r13, r13                     ; голова
    xor r14d, r14d                   ; количество
    xor edi, edi                     ; хвост
.pp_loop:
    call peek
    cmp eax, TOK_RPAREN
    je .pp_end
    cmp eax, TOK_EOF
    je .pp_end
    cmp eax, TOK_IDENT
    jne .pp_end
    call cur_tok                     ; r8=имя, r9d=длина
    push r8
    push r9
    inc r12
    call peek
    cmp eax, TOK_COLON
    jne .pp_notype
    inc r12
    call parse_type
    mov r10d, eax
    jmp .pp_mk
.pp_notype:
    mov r10d, TY_I32
.pp_mk:
    push r10
    call node_alloc
    pop r10
    pop r9
    pop r8
    mov rsi, rax
    mov qword [rsi + N_KIND], NODE_PARAM
    mov [rsi + N_A], r8
    mov [rsi + N_B], r9
    mov [rsi + N_C], r10
    cmp r13, 0
    jne .pp_link
    mov r13, rsi
    jmp .pp_after
.pp_link:
    mov [rdi + N_NEXT], rsi
.pp_after:
    mov rdi, rsi
    inc r14
    call peek
    cmp eax, TOK_COMMA
    jne .pp_loop
    inc r12
    jmp .pp_loop
.pp_end:
    cmp eax, TOK_RPAREN
    jne .pp_ret
    inc r12
.pp_ret:
    mov rax, r13
    mov ecx, r14d
    pop r14
    pop r13
    pop rdi
    pop rsi
    pop rbx
    ret

; parse_type: распознаёт имя типа, потребляет; eax = TY_* (по умолчанию i32)
parse_type:
    push rbx
    push rsi
    push rdx
    call peek
    cmp eax, TOK_IDENT
    jne .pt_def
    call cur_tok                     ; r8=ptr, r9d=len
    cmp r9, 3
    je .pt3
    cmp r9, 4
    je .pt4
    jmp .pt_def
.pt3:
    cmp byte [r8], 'i'
    jne .pt3s
    cmp byte [r8+1], '3'
    jne .pt3i64
    cmp byte [r8+2], '2'
    jne .pt_def
    inc r12
    mov eax, TY_I32
    jmp .pt_ret
.pt3i64:
    cmp byte [r8+1], '6'
    jne .pt_def
    cmp byte [r8+2], '4'
    jne .pt_def
    inc r12
    mov eax, TY_I64
    jmp .pt_ret
.pt3s:
    cmp byte [r8], 's'
    jne .pt3v
    cmp byte [r8+1], 't'
    jne .pt_def
    cmp byte [r8+2], 'r'
    jne .pt_def
    inc r12
    mov eax, TY_STR
    jmp .pt_ret
.pt3v:
    cmp byte [r8], 'i'
    jne .pt_def
    cmp byte [r8+1], 'n'
    jne .pt_def
    cmp byte [r8+2], 't'
    jne .pt_def
    inc r12
    mov eax, TY_I32
    jmp .pt_ret
.pt4:
    cmp byte [r8], 'b'
    jne .pt4v
    cmp byte [r8+1], 'o'
    jne .pt_def
    cmp byte [r8+2], 'o'
    jne .pt_def
    cmp byte [r8+3], 'l'
    jne .pt_def
    inc r12
    mov eax, TY_BOOL
    jmp .pt_ret
.pt4v:
    cmp byte [r8], 'v'
    jne .pt_def
    cmp byte [r8+1], 'o'
    jne .pt_def
    cmp byte [r8+2], 'i'
    jne .pt_def
    cmp byte [r8+3], 'd'
    jne .pt_def
    inc r12
    mov eax, TY_VOID
    jmp .pt_ret
.pt_def:
    mov eax, TY_I32
.pt_ret:
    pop rdx
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_block:
    push rbx
    push rsi
    push rdi
    push r13
    push r14
    push r15
    inc r12                          ; '{'
    call node_alloc
    mov r15, rax
    xor r13, r13                     ; голова
    xor r14d, r14d                   ; счётчик
    xor edi, edi                     ; хвост
.pb_loop:
    call peek
    cmp eax, TOK_RBRACE
    je .pb_end
    cmp eax, TOK_EOF
    je .pb_end
    call parse_stmt
    test rax, rax
    jz .pb_loop
    cmp r13, 0
    jne .pb_link
    mov r13, rax
    jmp .pb_after
.pb_link:
    mov [rdi + N_NEXT], rax
.pb_after:
    mov rdi, rax
    inc r14
    jmp .pb_loop
.pb_end:
    cmp eax, TOK_RBRACE
    jne .pb_ret
    inc r12
.pb_ret:
    mov [r15 + N_A], r13
    mov [r15 + N_B], r14
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_stmt:                            ; rax = узел-выражение (0 — пусто)
    push rbx
    call peek
    cmp eax, TOK_LET
    je .ps_let
    cmp eax, TOK_IF
    je .ps_if
    cmp eax, TOK_WHILE
    je .ps_while
    cmp eax, TOK_FOR
    je .ps_for
    cmp eax, TOK_RETURN
    je .ps_return
    cmp eax, TOK_CONST
    je .ps_let
    cmp eax, TOK_BREAK
    je .ps_skipkw
    cmp eax, TOK_CONTINUE
    je .ps_skipkw
    cmp eax, TOK_SEMI
    je .ps_semi
    cmp eax, TOK_IDENT
    jne .ps_expr
    ; присваивание? IDENT '='
    mov rax, r12
    inc rax
    call peek_at
    cmp eax, TOK_ASSIGN
    jne .ps_expr
    call parse_assign
    jmp .ps_ret
.ps_semi:
    inc r12
    xor eax, eax
    jmp .ps_ret
.ps_skipkw:
    inc r12
    call peek
    cmp eax, TOK_SEMI
    jne .ps_skipret
    inc r12
.ps_skipret:
    xor eax, eax
    jmp .ps_ret
.ps_let:
    call parse_let
    jmp .ps_ret
.ps_if:
    call parse_if
    jmp .ps_ret
.ps_while:
    call parse_while
    jmp .ps_ret
.ps_for:
    call parse_for
    jmp .ps_ret
.ps_return:
    call parse_return
    jmp .ps_ret
.ps_expr:
    call parse_expr
    mov rcx, rax
    call node_alloc
    mov rdx, rax
    mov qword [rdx + N_KIND], NODE_EXPRSTMT
    mov [rdx + N_A], rcx
    mov rax, rdx
    ; необязательная ';'
    push rax
    call peek
    cmp eax, TOK_SEMI
    jne .ps_expr_nosemi
    inc r12
.ps_expr_nosemi:
    pop rax
.ps_ret:
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_let:
    push rbx
    push rsi
    push r13
    push r14
    push r15
    inc r12                          ; 'let' / 'const'
    call peek
    cmp eax, TOK_IDENT
    jne .pl_err
    call cur_tok
    mov r13, r8                      ; имя
    mov r14d, r9d                    ; длина
    inc r12
    xor r15d, r15d                   ; 0 = аннотации нет
    call peek
    cmp eax, TOK_COLON
    jne .pl_notype
    inc r12
    call parse_type
    mov r15d, eax
.pl_notype:
    xor ecx, ecx                    ; init
    call peek
    cmp eax, TOK_ASSIGN
    jne .pl_mk
    inc r12
    call parse_expr
    mov rcx, rax
.pl_mk:
    push rcx
    call node_alloc
    pop rcx
    mov rsi, rax
    mov qword [rsi + N_KIND], NODE_LET
    mov [rsi + N_A], r13
    mov [rsi + N_B], r14
    mov [rsi + N_C], rcx
    mov [rsi + N_D], r15
    call peek
    cmp eax, TOK_SEMI
    jne .pl_ret
    inc r12
.pl_ret:
    mov rax, rsi
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pl_err:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_assign:
    push rbx
    push r13
    push r14
    call cur_tok
    mov r13, r8
    mov r14d, r9d
    inc r12                          ; имя
    inc r12                          ; '='
    call parse_expr
    mov rcx, rax
    call node_alloc
    mov rdx, rax
    mov qword [rdx + N_KIND], NODE_ASSIGN
    mov [rdx + N_A], r13
    mov [rdx + N_B], r14
    mov [rdx + N_C], rcx
    push rdx
    call peek
    cmp eax, TOK_SEMI
    jne .pa_nosemi
    inc r12
.pa_nosemi:
    pop rax
    pop r14
    pop r13
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_if:
    push rbx
    push r13
    push r14
    push r15
    inc r12                          ; 'if'
    call parse_expr
    mov r13, rax                     ; условие
    call peek
    cmp eax, TOK_LBRACE
    jne .pi_err
    call parse_block
    mov r14, rax                     ; then
    xor r15, r15                     ; else
    call peek
    cmp eax, TOK_ELSE
    jne .pi_mk
    inc r12
    call peek
    cmp eax, TOK_IF
    jne .pi_else_blk
    call parse_if
    mov r15, rax
    jmp .pi_mk
.pi_else_blk:
    cmp eax, TOK_LBRACE
    jne .pi_mk
    call parse_block
    mov r15, rax
.pi_mk:
    push r13
    push r14
    push r15
    call node_alloc
    pop rdx                          ; else
    pop rcx                          ; then
    pop rsi                          ; cond
    mov r8, rax
    mov qword [r8 + N_KIND], NODE_IF
    mov [r8 + N_A], rsi
    mov [r8 + N_B], rcx
    mov [r8 + N_C], rdx
    mov rax, r8
    pop r15
    pop r14
    pop r13
    pop rbx
    ret
.pi_err:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_while:
    push rbx
    push r13
    inc r12                          ; 'while'
    call parse_expr
    mov r13, rax
    call peek
    cmp eax, TOK_LBRACE
    jne .pw_err
    call parse_block
    mov rcx, rax
    call node_alloc
    mov rdx, rax
    mov qword [rdx + N_KIND], NODE_WHILE
    mov [rdx + N_A], r13
    mov [rdx + N_B], rcx
    mov rax, rdx
    pop r13
    pop rbx
    ret
.pw_err:
    xor eax, eax
    pop r13
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_for:
    push rbx
    push r13
    push r14
    push r15
    inc r12                          ; 'for'
    call peek
    cmp eax, TOK_IDENT
    jne .pf_err
    call cur_tok
    mov r13, r8                      ; имя переменной
    mov r14d, r9d
    inc r12
    call peek
    cmp eax, TOK_IN
    jne .pf_err
    inc r12
    call parse_expr
    push rax                         ; start
    call peek
    cmp eax, TOK_DOT2
    jne .pf_errsp
    inc r12
    call parse_expr
    mov r15, rax                     ; end
    call peek
    cmp eax, TOK_LBRACE
    jne .pf_errsp
    call parse_block
    mov rcx, rax                     ; тело
    pop rsi                          ; start
    push r13
    push r14
    push r15
    push rsi
    push rcx
    call node_alloc
    pop rdx                          ; тело
    pop rsi                          ; start
    pop r9                           ; end
    pop r8                           ; len
    pop rcx                          ; имя
    mov r10, rax
    mov qword [r10 + N_KIND], NODE_FOR
    mov [r10 + N_A], rcx
    mov [r10 + N_B], r8
    mov [r10 + N_C], rsi
    mov [r10 + N_D], r9
    mov [r10 + N_E], rdx
    mov rax, r10
    pop r15
    pop r14
    pop r13
    pop rbx
    ret
.pf_errsp:
    add rsp, 8
.pf_err:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_return:
    push rbx
    inc r12                          ; 'return'
    call peek
    cmp eax, TOK_SEMI
    je .pr_void
    cmp eax, TOK_RBRACE
    je .pr_void
    cmp eax, TOK_EOF
    je .pr_void
    call parse_expr
    mov rcx, rax
    jmp .pr_mk
.pr_void:
    xor ecx, ecx
.pr_mk:
    push rcx
    call node_alloc
    pop rcx
    mov rdx, rax
    mov qword [rdx + N_KIND], NODE_RETURN
    mov [rdx + N_A], rcx
    push rdx
    call peek
    cmp eax, TOK_SEMI
    jne .pr_nosemi
    inc r12
.pr_nosemi:
    pop rax
    pop rbx
    ret

; ---------------------------------------------------------------------------
; выражения: подъём по приоритетам
; ---------------------------------------------------------------------------
parse_expr:
    xor ecx, ecx
    jmp parse_prec

parse_prec:                            ; ecx = min_prec -> rax = узел
    push rbx
    push rsi
    push rdi
    push r13
    push r14
    push rcx
    call parse_unary
    mov r13, rax
.ppc_loop:
    call peek
    call map_binop
    test eax, eax
    jz .ppc_done
    mov r14d, eax
    call op_prec
    cmp eax, ecx
    jl .ppc_done
    inc r12                          ; поглощаем оператор
    inc eax
    mov ecx, eax
    call parse_prec                  ; правая часть с min_prec = p+1
    mov rsi, rax
    push r13
    push r14
    push rsi
    call node_alloc
    pop rdx                          ; right
    pop rcx                          ; op
    pop rsi                          ; left
    mov rdi, rax
    mov qword [rdi + N_KIND], NODE_EBIN
    mov [rdi + N_A], rcx
    mov [rdi + N_B], rsi
    mov [rdi + N_C], rdx
    mov r13, rdi
    jmp .ppc_loop
.ppc_done:
    mov rax, r13
    pop rcx
    pop r14
    pop r13
    pop rdi
    pop rsi
    pop rbx
    ret

; map_binop: peek -> eax = OP_* или 0
map_binop:
    cmp eax, TOK_PLUS
    je .mb_add
    cmp eax, TOK_MINUS
    je .mb_sub
    cmp eax, TOK_STAR
    je .mb_mul
    cmp eax, TOK_SLASH
    je .mb_div
    cmp eax, TOK_PERCENT
    je .mb_mod
    cmp eax, TOK_EQEQ
    je .mb_eq
    cmp eax, TOK_NEQ
    je .mb_ne
    cmp eax, TOK_LT
    je .mb_lt
    cmp eax, TOK_GT
    je .mb_gt
    cmp eax, TOK_LE
    je .mb_le
    cmp eax, TOK_GE
    je .mb_ge
    cmp eax, TOK_AND
    je .mb_and
    cmp eax, TOK_OR
    je .mb_or
    xor eax, eax
    ret
.mb_add: mov eax, OP_ADD
    ret
.mb_sub: mov eax, OP_SUB
    ret
.mb_mul: mov eax, OP_MUL
    ret
.mb_div: mov eax, OP_DIV
    ret
.mb_mod: mov eax, OP_MOD
    ret
.mb_eq: mov eax, OP_EQ
    ret
.mb_ne: mov eax, OP_NE
    ret
.mb_lt: mov eax, OP_LT
    ret
.mb_gt: mov eax, OP_GT
    ret
.mb_le: mov eax, OP_LE
    ret
.mb_ge: mov eax, OP_GE
    ret
.mb_and: mov eax, OP_AND
    ret
.mb_or: mov eax, OP_OR
    ret

; op_prec: eax = OP_* -> eax = приоритет
op_prec:
    cmp eax, OP_OR
    je .op1
    cmp eax, OP_AND
    je .op2
    cmp eax, OP_EQ
    je .op3
    cmp eax, OP_NE
    je .op3
    cmp eax, OP_LT
    je .op4
    cmp eax, OP_GT
    je .op4
    cmp eax, OP_LE
    je .op4
    cmp eax, OP_GE
    je .op4
    cmp eax, OP_ADD
    je .op5
    cmp eax, OP_SUB
    je .op5
    mov eax, 6
    ret
.op1: mov eax, 1
    ret
.op2: mov eax, 2
    ret
.op3: mov eax, 3
    ret
.op4: mov eax, 4
    ret
.op5: mov eax, 5
    ret

; ---------------------------------------------------------------------------
parse_unary:
    push rbx
    push r13
    push rcx                         ; min_prec вызывающего не портим
    call peek
    cmp eax, TOK_MINUS
    je .pu_neg
    cmp eax, TOK_NOT
    je .pu_not
    call parse_primary
    pop rcx
    pop r13
    pop rbx
    ret
.pu_neg:
    inc r12
    call parse_unary
    mov r13, rax
    call node_alloc
    mov qword [rax + N_KIND], NODE_EUN
    mov qword [rax + N_A], OP_NEG
    mov [rax + N_B], r13
    pop rcx
    pop r13
    pop rbx
    ret
.pu_not:
    inc r12
    call parse_unary
    mov r13, rax
    call node_alloc
    mov qword [rax + N_KIND], NODE_EUN
    mov qword [rax + N_A], OP_NOT
    mov [rax + N_B], r13
    pop rcx
    pop r13
    pop rbx
    ret

; ---------------------------------------------------------------------------
parse_primary:
    push rbx
    push rsi
    push r13
    push r14
    push r15
    push rcx                         ; min_prec вызывающего не портим
    call peek
    cmp eax, TOK_INT
    je .pp_int
    cmp eax, TOK_STRING
    je .pp_str
    cmp eax, TOK_TRUE
    je .pp_true
    cmp eax, TOK_FALSE
    je .pp_false
    cmp eax, TOK_LPAREN
    je .pp_paren
    cmp eax, TOK_IDENT
    je .pp_ident
    ; восстановление: пропускаем токен, возвращаем 0
    inc r12
    xor eax, eax
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pp_int:
    call cur_tok                     ; r8 = значение
    inc r12
    mov rcx, r8
    call node_alloc
    mov qword [rax + N_KIND], NODE_EINT
    mov [rax + N_A], rcx
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pp_str:
    call cur_tok                     ; r8=ptr, r9d=len
    inc r12
    push r8
    push r9
    call node_alloc
    pop r9
    pop r8
    mov qword [rax + N_KIND], NODE_ESTR
    mov [rax + N_A], r8
    mov [rax + N_B], r9
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pp_true:
    inc r12
    call node_alloc
    mov qword [rax + N_KIND], NODE_EBOOL
    mov qword [rax + N_A], 1
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pp_false:
    inc r12
    call node_alloc
    mov qword [rax + N_KIND], NODE_EBOOL
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pp_paren:
    inc r12
    call parse_expr
    push rax
    call peek
    cmp eax, TOK_RPAREN
    jne .pp_par_noclose
    inc r12
.pp_par_noclose:
    pop rax
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pp_ident:
    call cur_tok
    mov r13, r8                      ; имя
    mov r14d, r9d                    ; длина
    inc r12
    call peek
    cmp eax, TOK_LPAREN
    je .pp_call
    ; переменная
    call node_alloc
    mov qword [rax + N_KIND], NODE_EIDENT
    mov [rax + N_A], r13
    mov [rax + N_B], r14
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret
.pp_call:
    ; r13 = имя функции, r14d = длина (не трогаем их)
    inc r12                          ; '('
    xor r15, r15                     ; голова аргументов
    xor esi, esi                     ; хвост
    push qword 0                     ; счётчик аргументов (в стеке)
.ppc_argloop:
    call peek
    cmp eax, TOK_RPAREN
    je .ppc_argend
    cmp eax, TOK_EOF
    je .ppc_argend
    call parse_expr
    test rax, rax
    jz .ppc_argloop
    cmp r15, 0
    jne .ppc_link
    mov r15, rax
    jmp .ppc_after
.ppc_link:
    mov [rsi + N_NEXT], rax
.ppc_after:
    mov rsi, rax
    add qword [rsp], 1
    call peek
    cmp eax, TOK_COMMA
    jne .ppc_argloop
    inc r12
    jmp .ppc_argloop
.ppc_argend:
    cmp eax, TOK_RPAREN
    jne .ppc_noclose
    inc r12
.ppc_noclose:
    pop rcx                          ; количество аргументов
    push rcx
    call node_alloc
    pop rcx
    mov qword [rax + N_KIND], NODE_ECALL
    mov [rax + N_A], r13             ; имя функции
    mov [rax + N_B], r14             ; длина имени
    mov [rax + N_C], rcx             ; argc
    mov [rax + N_D], r15             ; голова аргументов
    pop rcx
    pop r15
    pop r14
    pop r13
    pop rsi
    pop rbx
    ret

; =============================================================================
; СЕМАНТИЧЕСКИЙ АНАЛИЗ
;   таблица переменных: r13 (запись 32 байта: ptr, len, slot, тип),
;   r14 = следующий свободный слот, r15 = число записей
; =============================================================================

; запись записи: r8=ptr, r9=len, ecx=тип -> eax=слот
add_var:
    push rbx
    push rsi
    push rdx
    ; уже есть?
    xor edx, edx
.av_scan:
    cmp rdx, r15
    jge .av_add
    mov rsi, rdx
    shl rsi, 5                   ; запись 32 байта
    add rsi, r13
    cmp [rsi + 8], r9
    jne .av_next
    mov rax, [rsi]
    ; сравнение имени
    push rdi
    push rcx
    mov rdi, rax
    mov rax, rsi
    call mem_eq                  ; rdi=имя в таблице, r8=новое, r9=len -> al
    pop rcx
    pop rdi
    test al, al
    jnz .av_dup
.av_next:
    inc rdx
    jmp .av_scan
.av_add:
    cmp r15, 256
    jge .av_full
    mov rsi, r15
    shl rsi, 5
    add rsi, r13
    mov [rsi], r8
    mov [rsi + 8], r9
    mov [rsi + 16], r14d
    mov [rsi + 20], ecx
    mov eax, r14d
    inc r15
    cmp ecx, TY_STR
    jne .av_adv1
    add r14d, 2
    jmp .av_ret
.av_adv1:
    inc r14d
.av_ret:
    pop rdx
    pop rsi
    pop rbx
    ret
.av_dup:
    ; повторное объявление — ошибка, но используем прежний слот
    mov eax, [rsi + 16]
    push rax
    mov rsi, [rsi]               ; имя переменной
    mov rdx, VA_RDATA(msg_redef)
    mov r8, 17
    call diag_named
    pop rax
    pop rdx
    pop rsi
    pop rbx
    ret
.av_full:
    xor eax, eax
    pop rdx
    pop rsi
    pop rbx
    ret

; поиск: r8=ptr, r9=len -> eax=слот (-1 если нет), ecx=тип
sema_lookup:
    push rbx
    push rsi
    push rdx
    xor edx, edx
.sl_scan:
    cmp rdx, r15
    jge .sl_notfound
    mov rsi, rdx
    shl rsi, 5
    add rsi, r13
    cmp [rsi + 8], r9
    jne .sl_next
    mov rax, [rsi]
    push rdi
    mov rdi, rax
    call mem_eq
    pop rdi
    test al, al
    jnz .sl_found
.sl_next:
    inc rdx
    jmp .sl_scan
.sl_found:
    mov eax, [rsi + 16]
    mov ecx, [rsi + 20]
    pop rdx
    pop rsi
    pop rbx
    ret
.sl_notfound:
    mov eax, -1
    xor ecx, ecx
    pop rdx
    pop rsi
    pop rbx
    ret

; mem_eq: rdi=a, r8=b, r9=len -> al=1 если равны
mem_eq:
    push rcx
    push rsi
    xor ecx, ecx
.me_loop:
    cmp rcx, r9
    jge .me_eq
    mov al, [rdi + rcx]
    cmp al, [r8 + rcx]
    jne .me_ne
    inc rcx
    jmp .me_loop
.me_eq:
    mov al, 1
    pop rsi
    pop rcx
    ret
.me_ne:
    xor al, al
    pop rsi
    pop rcx
    ret

; is_intrinsic: r8=имя, r9=len -> al=1 (print/println), ecx: 1=print,2=println
is_intrinsic:
    cmp r9, 5
    jne .ii_p2
    cmp dword [r8], 'prin'
    jne .ii_no
    cmp byte [r8+4], 't'
    jne .ii_no
    mov al, 1
    mov ecx, 1
    ret
.ii_p2:
    cmp r9, 7
    jne .ii_no
    cmp dword [r8], 'prin'
    jne .ii_no
    cmp dword [r8+3], 'ntln'
    jne .ii_no
    mov al, 1
    mov ecx, 2
    ret
.ii_no:
    xor al, al
    xor ecx, ecx
    ret

; sema_find_func: r8=имя, r9=len -> eax=func_id или -1
sema_find_func:
    push rbx
    push rsi
    push rdi
    push rcx
    push rdx
    mov rsi, [rbx + G_FUNC]
    mov rdx, [rbx + G_FUNCCNT]
    xor ecx, ecx
.sf_loop:
    cmp rcx, rdx
    jge .sf_notfound
    mov rdi, [rsi + rcx*8]
    push rcx
    mov rax, [rdi + N_B]
    cmp rax, r9
    jne .sf_next
    mov rdi, [rdi + N_A]
    call mem_eq
    test al, al
    jnz .sf_found_pop
.sf_next:
    pop rcx
    inc rcx
    jmp .sf_loop
.sf_found_pop:
    pop rcx
.sf_found:
    mov eax, ecx
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    pop rbx
    ret
.sf_notfound:
    mov eax, -1
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; диагностики: "error: <msg><имя>\n"; diag_named: rdx=msg, r8=len,
;              rsi=имя (ptr), r9=len имени
; ---------------------------------------------------------------------------
diag_named:
    push rbx
    push rsi                       ; указатель имени
    push rdi
    push r12
    push r13
    push r8                        ; длина сообщения
    push r9                        ; длина имени
    push rdx                       ; сообщение
    mov ecx, -12
    API COMP_GetStdHandle
    mov r12, rax
    mov rdx, VA_RDATA(msg_error_prefix)
    mov r8, 7
    call comp_write
    pop rdx                        ; сообщение
    pop r13                        ; длина имени (сохранённый r9):
                                   ; r11 не годится — API портят и его
    pop r8                         ; длина сообщения (сохранённый r8)
    call comp_write                ; сообщение
    mov rdx, rsi                   ; указатель имени (из сохранённого rsi)
    mov r8, r13                    ; длина имени
    call comp_write
    mov rdx, VA_RDATA(msg_newline)
    mov r8, 2
    call comp_write
    inc qword [rbx + G_ERRCNT]
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; diag_plain: rdx=msg, r8=len — без имени
diag_plain:
    push rbx
    push r12
    mov ecx, -12
    API COMP_GetStdHandle
    mov r12, rax
    push rdx
    push r8
    mov rdx, VA_RDATA(msg_error_prefix)
    mov r8, 7
    call comp_write
    pop r8
    pop rdx
    call comp_write
    mov rdx, VA_RDATA(msg_newline)
    mov r8, 2
    call comp_write
    inc qword [rbx + G_ERRCNT]
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
sema:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    mov rsi, [rbx + G_FUNC]
    mov r12, [rbx + G_FUNCCNT]
    ; func_id + дубликаты
    xor ecx, ecx
.sm_floop:
    cmp rcx, r12
    jge .sm_fdone
    mov rdi, [rsi + rcx*8]
    mov [rdi + N_F], rcx
    ; дубликат среди предыдущих?
    xor r13, r13
.sm_dup:
    cmp r13, rcx
    jge .sm_dupdone
    push rcx
    push rsi
    mov rsi, [rbx + G_FUNC]
    mov rax, [rsi + rcx*8]
    mov rdx, [rax + N_B]
    mov r9, rdx
    mov r8, [rax + N_A]
    mov rax, [rsi + r13*8]
    cmp [rax + N_B], r9
    jne .sm_dupnext
    push rdi
    mov rdi, [rax + N_A]
    call mem_eq
    pop rdi
    test al, al
    jz .sm_dupnext
    ; дубликат!
    mov rdx, VA_RDATA(msg_redef)
    mov r8, 17
    mov rsi, [rax + N_A]
    mov r9, [rax + N_B]
    call diag_named
.sm_dupnext:
    pop rsi
    pop rcx
    inc r13
    jmp .sm_dup
.sm_dupdone:
    inc rcx
    jmp .sm_floop
.sm_fdone:
    ; main должна существовать
    push rsi
    mov r8, VA_RDATA(msg_main_name)
    mov r9, 4
    call sema_find_func
    pop rsi
    cmp eax, -1
    jne .sm_have_main
    mov rdx, VA_RDATA(msg_no_main)
    mov r8, 25
    call diag_plain
.sm_have_main:
    ; разбор каждой функции
    xor ecx, ecx
.sm_gloop:
    cmp rcx, r12
    jge .sm_done
    push rsi
    push rcx
    mov rsi, [rbx + G_FUNC]
    mov rdi, [rsi + rcx*8]
    call sema_func
    pop rcx
    pop rsi
    inc rcx
    jmp .sm_gloop
.sm_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; sema_func: rdi = узел функции
sema_func:
    push rbx
    push rsi
    push rdi
    push r13
    push r14
    push r15
    mov rcx, 256*32
    call heap_alloc
    mov r13, rax
    xor r15, r15
    mov r14d, 1
    ; параметры
    mov rsi, [rdi + N_C]
.sfp_loop:
    cmp rsi, 0
    je .sfp_done
    mov r8, [rsi + N_A]
    mov r9, [rsi + N_B]
    mov ecx, [rsi + N_C]
    cmp ecx, TY_STR                 ; строковых параметров нет — один слот
    jne .sfp_add
    mov ecx, TY_I32
.sfp_add:
    call add_var
    mov rsi, [rsi + N_NEXT]
    jmp .sfp_loop
.sfp_done:
    ; тело (узел функции храним в стеке)
    push rdi
    mov rdi, [rdi + N_E]
    call sema_resolve_block
    pop rdi
    mov [rdi + N_G], r14            ; следующий свободный слот
    pop r15
    pop r14
    pop r13
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; sema_resolve_block: rdi = блок
; ---------------------------------------------------------------------------
sema_resolve_block:
    push rbx
    push rsi
    push rdi
    push r12
    cmp rdi, 0
    je .srb_done
    mov rsi, [rdi + N_A]
.srb_loop:
    cmp rsi, 0
    je .srb_done
    mov eax, [rsi + N_KIND]
    cmp eax, NODE_LET
    je .srb_let
    cmp eax, NODE_ASSIGN
    je .srb_assign
    cmp eax, NODE_IF
    je .srb_if
    cmp eax, NODE_WHILE
    je .srb_while
    cmp eax, NODE_FOR
    je .srb_for
    cmp eax, NODE_RETURN
    je .srb_return
    cmp eax, NODE_EXPRSTMT
    je .srb_exprst
    jmp .srb_next
.srb_let:
    mov rdi, [rsi + N_C]
    call sema_resolve_expr
    ; аннотация: [rsi+N_D] (0 — её не было)
    mov ecx, [rsi + N_D]
    cmp qword [rsi + N_C], 0
    je .srb_let_have
    mov rdi, [rsi + N_C]
    cmp qword [rdi + N_KIND], NODE_ESTR
    jne .srb_let_noinitstr
    ; инициализация строковым литералом
    test ecx, ecx
    jz .srb_let_setstr
    cmp ecx, TY_STR
    je .srb_let_have
    push rsi
    mov rdx, VA_RDATA(msg_type_mismatch)
    mov r8, 33
    mov r9, [rsi + N_B]
    mov rsi, [rsi + N_A]     ; имя — последним, портим rsi
    call diag_named
    pop rsi
    mov ecx, TY_STR
    jmp .srb_let_have
.srb_let_setstr:
    mov ecx, TY_STR
    jmp .srb_let_have
.srb_let_noinitstr:
    cmp ecx, TY_STR
    jne .srb_let_have
    ; аннотация str, но инициализация не строкой
    push rsi
    mov rdx, VA_RDATA(msg_type_mismatch)
    mov r8, 33
    mov r9, [rsi + N_B]
    mov rsi, [rsi + N_A]     ; имя — последним, портим rsi
    call diag_named
    pop rsi
    mov ecx, TY_I32
.srb_let_have:
    test ecx, ecx
    jnz .srb_let_tyok
    ; вывод типа из инициализации
    cmp qword [rsi + N_C], 0
    je .srb_let_i32
    mov rdi, [rsi + N_C]
    mov ecx, [rdi + N_D]
    test ecx, ecx
    jnz .srb_let_tyok
.srb_let_i32:
    mov ecx, TY_I32
.srb_let_tyok:
    mov [rsi + N_D], rcx
    mov r8, [rsi + N_A]
    mov r9, [rsi + N_B]
    call add_var
    mov [rsi + N_F], rax
    jmp .srb_next
.srb_assign:
    mov r8, [rsi + N_A]
    mov r9, [rsi + N_B]
    call sema_lookup
    cmp eax, -1
    jne .srb_as_ok
    push rsi
    mov rdx, VA_RDATA(msg_undef_var)
    mov r8, 20
    mov r9, [rsi + N_B]
    mov rsi, [rsi + N_A]     ; имя — последним, портим rsi
    call diag_named
    pop rsi
    jmp .srb_next
.srb_as_ok:
    mov [rsi + N_F], rax         ; слот
    mov r12d, ecx                 ; тип переменной
    mov rdi, [rsi + N_C]
    call sema_resolve_expr
    ; проверка типа: строковая переменная <- только строковый литерал
    cmp r12d, TY_STR
    jne .srb_as_int
    cmp qword [rsi + N_C], 0
    je .srb_next
    mov rdi, [rsi + N_C]
    cmp qword [rdi + N_KIND], NODE_ESTR
    je .srb_next
    push rsi
    mov rdx, VA_RDATA(msg_type_mismatch)
    mov r8, 33
    mov r9, [rsi + N_B]
    mov rsi, [rsi + N_A]     ; имя — последним, портим rsi
    call diag_named
    pop rsi
    jmp .srb_next
.srb_as_int:
    cmp qword [rsi + N_C], 0
    je .srb_next
    mov rdi, [rsi + N_C]
    cmp qword [rdi + N_KIND], NODE_ESTR
    jne .srb_next
    push rsi
    mov rdx, VA_RDATA(msg_type_mismatch)
    mov r8, 33
    mov r9, [rsi + N_B]
    mov rsi, [rsi + N_A]     ; имя — последним, портим rsi
    call diag_named
    pop rsi
    jmp .srb_next
.srb_if:
    mov rdi, [rsi + N_A]
    call sema_resolve_expr
    mov rdi, [rsi + N_B]
    call sema_resolve_block
    cmp qword [rsi + N_C], 0
    je .srb_next
    mov rdi, [rsi + N_C]
    call sema_resolve_block
    jmp .srb_next
.srb_while:
    mov rdi, [rsi + N_A]
    call sema_resolve_expr
    mov rdi, [rsi + N_B]
    call sema_resolve_block
    jmp .srb_next
.srb_for:
    mov rdi, [rsi + N_C]
    call sema_resolve_expr
    mov rdi, [rsi + N_D]
    call sema_resolve_expr
    mov r8, [rsi + N_A]
    mov r9, [rsi + N_B]
    mov ecx, TY_I32
    call add_var                 ; слот переменной (+ сам занимает 1)
    mov [rsi + N_F], rax
    inc r14d                     ; второй слот — под значение конца
    mov rdi, [rsi + N_E]
    call sema_resolve_block
    jmp .srb_next
.srb_return:
    cmp qword [rsi + N_A], 0
    je .srb_next
    mov rdi, [rsi + N_A]
    call sema_resolve_expr
    jmp .srb_next
.srb_exprst:
    mov rdi, [rsi + N_A]
    call sema_resolve_expr
.srb_next:
    mov rsi, [rsi + N_NEXT]
    jmp .srb_loop
.srb_done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; sema_resolve_expr: rdi = узел выражения (0 допустимо)
; ---------------------------------------------------------------------------
sema_resolve_expr:
    push rbx
    push rsi
    push rdi
    push r12
    cmp rdi, 0
    je .sre_done
    mov eax, [rdi + N_KIND]
    cmp eax, NODE_EINT
    je .sre_int
    cmp eax, NODE_ESTR
    je .sre_str
    cmp eax, NODE_EBOOL
    je .sre_bool
    cmp eax, NODE_EIDENT
    je .sre_ident
    cmp eax, NODE_EBIN
    je .sre_bin
    cmp eax, NODE_EUN
    je .sre_un
    cmp eax, NODE_ECALL
    je .sre_call
    jmp .sre_done
.sre_int:
    mov qword [rdi + N_D], TY_I32
    jmp .sre_done
.sre_str:
    mov qword [rdi + N_D], TY_STR
    jmp .sre_done
.sre_bool:
    mov qword [rdi + N_D], TY_BOOL
    jmp .sre_done
.sre_ident:
    mov r8, [rdi + N_A]
    mov r9, [rdi + N_B]
    call sema_lookup
    cmp eax, -1
    jne .sre_id_ok
    push rdi
    mov rdx, VA_RDATA(msg_undef_var)
    mov r8, 20
    mov rsi, [rdi + N_A]
    mov r9, [rdi + N_B]
    call diag_named
    pop rdi
    jmp .sre_done
.sre_id_ok:
    mov [rdi + N_F], rax         ; слот
    mov [rdi + N_D], rcx         ; тип
    jmp .sre_done
.sre_bin:
    mov rsi, [rdi + N_B]
    call sema_resolve_expr_rsi
    mov rsi, [rdi + N_C]
    call sema_resolve_expr_rsi
    ; свёртка констант
    mov rsi, [rdi + N_B]
    mov r12, [rdi + N_C]
    cmp qword [rsi + N_KIND], NODE_EINT
    jne .sre_bin_nofold
    cmp qword [r12 + N_KIND], NODE_EINT
    jne .sre_bin_nofold
    call sema_fold_bin
    jmp .sre_done
.sre_bin_nofold:
    ; тип результата
    mov eax, [rdi + N_A]
    cmp eax, OP_EQ
    je .sre_bin_bool
    cmp eax, OP_NE
    je .sre_bin_bool
    cmp eax, OP_LT
    je .sre_bin_bool
    cmp eax, OP_GT
    je .sre_bin_bool
    cmp eax, OP_LE
    je .sre_bin_bool
    cmp eax, OP_GE
    je .sre_bin_bool
    cmp eax, OP_AND
    je .sre_bin_bool
    cmp eax, OP_OR
    je .sre_bin_bool
    mov rsi, [rdi + N_B]
    mov rax, [rsi + N_D]
    mov [rdi + N_D], rax
    jmp .sre_done
.sre_bin_bool:
    mov qword [rdi + N_D], TY_BOOL
    jmp .sre_done
.sre_un:
    mov rsi, [rdi + N_B]
    call sema_resolve_expr_rsi
    cmp qword [rdi + N_A], OP_NOT
    jne .sre_un_neg
    mov qword [rdi + N_D], TY_BOOL
    ; свёртка !константы
    mov rsi, [rdi + N_B]
    cmp qword [rsi + N_KIND], NODE_EBOOL
    jne .sre_done
    mov rax, [rsi + N_A]
    xor rax, 1
    mov qword [rdi + N_KIND], NODE_EBOOL
    mov [rdi + N_A], rax
    mov qword [rdi + N_B], 0
    jmp .sre_done
.sre_un_neg:
    mov rsi, [rdi + N_B]
    mov rax, [rsi + N_D]
    mov [rdi + N_D], rax
    cmp qword [rsi + N_KIND], NODE_EINT
    jne .sre_done
    mov rax, [rsi + N_A]
    neg rax
    mov qword [rdi + N_KIND], NODE_EINT
    mov [rdi + N_A], rax
    mov qword [rdi + N_B], 0
    jmp .sre_done
.sre_call:
    mov r8, [rdi + N_A]
    mov r9, [rdi + N_B]
    call is_intrinsic
    test al, al
    jnz .sre_intr
    call sema_find_func
    cmp eax, -1
    jne .sre_call_found
    push rdi
    mov rdx, VA_RDATA(msg_undef_func)
    mov r8, 20
    mov rsi, [rdi + N_A]
    mov r9, [rdi + N_B]
    call diag_named
    pop rdi
    mov qword [rdi + N_E], 0
    mov qword [rdi + N_F], -1
    jmp .sre_call_args
.sre_call_found:
    mov [rdi + N_F], rax         ; func_id
    mov qword [rdi + N_E], 0
    ; количество аргументов
    push rdi
    push rax
    mov rsi, [rbx + G_FUNC]
    pop rax
    mov rsi, [rsi + rax*8]
    mov ecx, [rsi + N_D]         ; nparams
    mov eax, [rdi + N_C]         ; argc
    cmp eax, ecx
    je .sre_call_arity_ok
    mov rdx, VA_RDATA(msg_arity)
    mov r8, 31
    mov rsi, [rdi + N_A]
    mov r9, [rdi + N_B]
    call diag_named
.sre_call_arity_ok:
    pop rdi
    ; тип результата — тип возврата функции.
    ; ВАЖНО: храним в N_G, а не в N_D — в N_D лежит голова аргументов!
    push rdi
    mov rsi, [rbx + G_FUNC]
    mov eax, [rdi + N_F]
    mov rsi, [rsi + rax*8]
    mov rax, [rsi + N_D]
    shr rax, 32
    mov [rdi + N_G], rax
    pop rdi
    jmp .sre_call_args
.sre_intr:
    mov qword [rdi + N_E], 1
    cmp qword [rdi + N_C], 1
    jle .sre_call_args
    push rdi
    mov rdx, VA_RDATA(msg_intrinsic_arity)
    mov r8, 37
    call diag_plain
    pop rdi
.sre_call_args:
    mov rsi, [rdi + N_D]
.sre_args_loop:
    cmp rsi, 0
    je .sre_done
    call sema_resolve_expr_rsi
    mov rsi, [rsi + N_NEXT]
    jmp .sre_args_loop
.sre_done:
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; обёртка: разобрать выражение в rsi
sema_resolve_expr_rsi:
    push rdi
    mov rdi, rsi
    call sema_resolve_expr
    pop rdi
    ret

; свёртка: rdi = EBIN, rsi = левый (EINT), r12 = правый (EINT)
sema_fold_bin:
    push rdx
    push rcx
    mov rax, [rsi + N_A]         ; левое значение
    mov rcx, [r12 + N_A]         ; правое значение
    mov edx, [rdi + N_A]         ; операция
    cmp edx, OP_ADD
    je .sf_add
    cmp edx, OP_SUB
    je .sf_sub
    cmp edx, OP_MUL
    je .sf_mul
    cmp edx, OP_DIV
    je .sf_div
    cmp edx, OP_MOD
    je .sf_div
    cmp edx, OP_EQ
    je .sf_cmp
    cmp edx, OP_NE
    je .sf_cmp
    cmp edx, OP_LT
    je .sf_cmp
    cmp edx, OP_GT
    je .sf_cmp
    cmp edx, OP_LE
    je .sf_cmp
    cmp edx, OP_GE
    je .sf_cmp
    cmp edx, OP_AND
    je .sf_and
    cmp edx, OP_OR
    je .sf_or
    jmp .sf_ret
.sf_add:
    add rax, rcx
    jmp .sf_int
.sf_sub:
    sub rax, rcx
    jmp .sf_int
.sf_mul:
    imul rax, rcx
    jmp .sf_int
.sf_div:
    test rcx, rcx
    jz .sf_ret                    ; деление на 0 не сворачиваем
    mov r10d, edx                 ; операция (idiv портит rdx)
    cqo
    idiv rcx
    cmp r10d, OP_MOD
    jne .sf_int
    mov rax, rdx
    jmp .sf_int
.sf_and:
    and rax, rcx
    jmp .sf_int
.sf_or:
    or rax, rcx
    jmp .sf_int
.sf_cmp:
    cmp rax, rcx
    mov eax, 0
    sete al
    cmp edx, OP_EQ
    je .sf_bool
    mov rax, [rsi + N_A]
    cmp rax, rcx
    mov eax, 0
    setne al
    cmp edx, OP_NE
    je .sf_bool
    mov rax, [rsi + N_A]
    cmp rax, rcx
    mov eax, 0
    setl al
    cmp edx, OP_LT
    je .sf_bool
    mov rax, [rsi + N_A]
    cmp rax, rcx
    mov eax, 0
    setg al
    cmp edx, OP_GT
    je .sf_bool
    mov rax, [rsi + N_A]
    cmp rax, rcx
    mov eax, 0
    setle al
    cmp edx, OP_LE
    je .sf_bool
    mov rax, [rsi + N_A]
    cmp rax, rcx
    mov eax, 0
    setge al
    jmp .sf_bool
.sf_int:
    mov qword [rdi + N_KIND], NODE_EINT
    mov [rdi + N_A], rax
    mov qword [rdi + N_B], 0
    mov qword [rdi + N_C], 0
    mov qword [rdi + N_D], TY_I32
.sf_ret:
    pop rcx
    pop rdx
    ret
.sf_bool:
    mov qword [rdi + N_KIND], NODE_EBOOL
    mov [rdi + N_A], rax
    mov qword [rdi + N_B], 0
    mov qword [rdi + N_C], 0
    mov qword [rdi + N_D], TY_BOOL
    pop rcx
    pop rdx
    ret

; =============================================================================
; ГЕНЕРАЦИЯ КОДА
; =============================================================================

; --- примитивы эмиссии -------------------------------------------------------

; emit_seq: копирует rcx байт из [rsi] в буфер кода (портит rdi)
emit_seq:
    push rbx
    push rdi
    push rax                         ; al используется как буфер копирования
    mov rdi, [rbx + G_CODECUR]
.es_cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .es_cp
    mov [rbx + G_CODECUR], rdi
    pop rax
    pop rdi
    pop rbx
    ret

; EMIT b1, b2, ... — вставить байты (данные лежат прямо в .тексте)
%macro EMIT 1-*
    lea rsi, [rel %%d]
    mov ecx, %0
    call emit_seq
    jmp short %%a
%%d:
%rotate 0
%rep %0
    db %1
%rotate 1
%endrep
%%a:
%endmacro

; emit_eax_dword: дописать двойное слово из eax
emit_eax_dword:
    push rbx
    push rdi
    mov rdi, [rbx + G_CODECUR]
    mov [rdi], eax
    add qword [rbx + G_CODECUR], 4
    pop rdi
    pop rbx
    ret

; emit_rax_qword: дописать 8 байт из rax
emit_rax_qword:
    push rbx
    push rdi
    mov rdi, [rbx + G_CODECUR]
    mov [rdi], rax
    add qword [rbx + G_CODECUR], 8
    pop rdi
    pop rbx
    ret

; new_label: rax = новый id метки
new_label:
    push rbx
    mov rax, [rbx + G_LABELCNT]
    cmp rax, 8192
    jge .nl_full
    inc qword [rbx + G_LABELCNT]
.nl_full:
    pop rbx
    ret

; bind_label: ecx = id; привязать к текущей позиции кода
bind_label:
    push rbx
    push rsi
    mov rsi, [rbx + G_LABELS]
    mov rax, [rbx + G_CODECUR]
    sub rax, [rbx + G_CODE]
    mov [rsi + rcx*8], rax
    pop rsi
    pop rbx
    ret

; cg_add_fixup: ecx = метка; на текущей позиции будет rel32 (4 нуля + запись)
cg_add_fixup:
    push rbx
    push rsi
    push rax
    push rdx
    mov rsi, [rbx + G_CODE]
    mov rax, [rbx + G_CODECUR]
    sub rax, rsi                    ; позиция поля rel32
    mov rsi, [rbx + G_FIXPOS]
    mov rdx, [rbx + G_FIXCNT]
    mov [rsi + rdx*8], rax
    mov rsi, [rbx + G_FIXLAB]
    mov [rsi + rdx*8], rcx
    inc qword [rbx + G_FIXCNT]
    xor eax, eax
    call emit_eax_dword
    pop rdx
    pop rax
    pop rsi
    pop rbx
    ret

; cg_call_label: E8 rel32 на метку ecx
; (EMIT/emit_seq портят rcx — метку сохраняем в стеке)
cg_call_label:
    push rcx
    EMIT 0xE8
    pop rcx
    call cg_add_fixup
    ret

; cg_jmp_label: E9 rel32
cg_jmp_label:
    push rcx
    EMIT 0xE9
    pop rcx
    call cg_add_fixup
    ret

; cg_jz_label: 0F 84 rel32
cg_jz_label:
    push rcx
    EMIT 0x0F, 0x84
    pop rcx
    call cg_add_fixup
    ret

; cg_jge_label: 0F 8D rel32
cg_jge_label:
    push rcx
    EMIT 0x0F, 0x8D
    pop rcx
    call cg_add_fixup
    ret

; cg_load_slot: eax = слот -> эмит  mov rax, [rbp-8*slot]
cg_load_slot:
    EMIT 0x48, 0x8B, 0x85
    shl eax, 3
    neg eax                          ; -(8*slot)
    call emit_eax_dword
    ret

; cg_store_slot: eax = слот -> эмит  mov [rbp-8*slot], rax
cg_store_slot:
    push rdx
    EMIT 0x48, 0x89, 0x85
    mov edx, eax
    shl edx, 3
    neg edx                          ; -(8*slot)
    mov eax, edx
    call emit_eax_dword
    pop rdx
    ret

; cg_store_rcx_slot: eax = слот -> эмит  mov [rbp-8*slot], rcx
cg_store_rcx_slot:
    push rdx
    EMIT 0x48, 0x89, 0x8D
    mov edx, eax
    shl edx, 3
    neg edx                          ; -(8*slot)
    mov eax, edx
    call emit_eax_dword
    pop rdx
    ret

; cg_mov_mem_imm32: eax = слот, ecx = imm32 -> mov qword [rbp-8*slot], ecx
cg_mov_mem_imm32:
    push rcx
    EMIT 0x48, 0xC7, 0x85
    shl eax, 3
    neg eax                          ; -(8*slot)
    call emit_eax_dword
    pop rax
    call emit_eax_dword
    ret

; cg_inc_slot: eax = слот -> inc qword [rbp-8*slot]
cg_inc_slot:
    EMIT 0x48, 0xFF, 0x85
    shl eax, 3
    neg eax                          ; -(8*slot)
    call emit_eax_dword
    ret

; cg_iat_call: rax = VA слота IAT цели -> эмит  mov rax,imm64; mov rax,[rax]; call rax
cg_iat_call:
    EMIT 0x48, 0xB8
    call emit_rax_qword
    EMIT 0x48, 0x8B, 0x00
    EMIT 0xFF, 0xD0
    ret

; cg_add_string: r8 = ptr, r9 = len -> eax = смещение в .rdata цели
cg_add_string:
    push rbx
    push rsi
    push rdi
    push rcx
    mov rdi, [rbx + G_RDATACUR]
    lea rax, [rdi + r9 + 1]
    cmp rax, [rbx + G_RDATAEND]
    jg .cas_oom
    mov [rbx + G_RDATACUR], rax
    mov rsi, r8
    mov rcx, r9
    mov r11, rdi                   ; начало строки в .rdata цели
    test rcx, rcx                  ; пустая строка — копировать нечего
    jz .cas_cpd
.cas_cp:
    mov al, [rsi]
    mov [r11], al
    inc rsi
    inc r11
    dec rcx
    jnz .cas_cp
.cas_cpd:
    mov byte [rdi + r9], 0         ; NUL после строки
    mov rax, rdi
    sub rax, [rbx + G_RDATA]
    pop rcx
    pop rdi
    pop rsi
    pop rbx
    ret
.cas_oom:
    mov rdx, VA_RDATA(msg_out_of_mem)
    mov r8, 13
    call fatal_err

; ---------------------------------------------------------------------------
; codegen: точка входа генерации
; ---------------------------------------------------------------------------
codegen:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    mov rax, [rbx + G_FUNCCNT]
    add rax, LAB_FUNC_BASE
    mov [rbx + G_LABELCNT], rax
    ; метка 0: вход
    mov ecx, LAB_ENTRY
    call bind_label
    call cg_emit_entry
    ; метка 1: print_str
    mov ecx, LAB_PRINTSTR
    call bind_label
    call cg_emit_print_str
    ; метка 2: print_int
    mov ecx, LAB_PRINTINT
    call bind_label
    call cg_emit_print_int
    ; метка 3: перевод строки
    mov ecx, LAB_NEWLINE
    call bind_label
    call cg_emit_newline
    ; функции
    mov rsi, [rbx + G_FUNC]
    mov r12, [rbx + G_FUNCCNT]
    xor ecx, ecx
.cgn_loop:
    cmp rcx, r12
    jge .cgn_done
    push rcx
    push rsi
    mov rdi, [rsi + rcx*8]
    mov eax, ecx
    add eax, LAB_FUNC_BASE
    call cg_emit_func
    pop rsi
    pop rcx
    inc rcx
    jmp .cgn_loop
.cgn_done:
    call patch_fixups
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; патч всех rel32-фиксапов
patch_fixups:
    push rbx
    push rsi
    push rdx
    push r8
    push r9
    mov rcx, [rbx + G_FIXCNT]
    xor edx, edx
.pf_loop:
    cmp rdx, rcx
    jge .pf_done
    mov rsi, [rbx + G_FIXPOS]
    mov r8, [rsi + rdx*8]          ; позиция поля
    mov rsi, [rbx + G_FIXLAB]
    mov r9, [rsi + rdx*8]          ; метка
    mov rsi, [rbx + G_LABELS]
    mov r9, [rsi + r9*8]           ; смещение цели
    mov rax, r9
    sub rax, r8
    sub rax, 4
    mov rsi, [rbx + G_CODE]
    mov [rsi + r8], eax
    inc rdx
    jmp .pf_loop
.pf_done:
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; входной блоб генерируемой программы
; ---------------------------------------------------------------------------
cg_emit_entry:
    push rbx
    ; найти main
    mov r8, VA_RDATA(msg_main_name)
    mov r9, 4
    call sema_find_func
    cmp eax, -1
    jne .ce_ok
    ; нет main (sema уже сообщила) — сразу выход 0
    EMIT 0x31, 0xC9                  ; xor ecx, ecx
    mov rax, GEN_ExitProcess
    call cg_iat_call
    pop rbx
    ret
.ce_ok:
    add eax, LAB_FUNC_BASE
    push rax                         ; метка main
    lea rsi, [rel gen_entry_p1]
    mov ecx, gen_entry_p1_len
    call emit_seq
    pop rcx
    call cg_call_label               ; call main
    lea rsi, [rel gen_entry_p2]
    mov ecx, gen_entry_p2_len
    call emit_seq
    pop rbx
    ret

cg_emit_print_str:
    lea rsi, [rel gen_ps_code]
    mov ecx, gen_ps_len
    call emit_seq
    ret

cg_emit_print_int:
    lea rsi, [rel gen_pi_code]
    mov ecx, gen_pi_len
    call emit_seq
    ret

cg_emit_newline:
    lea rsi, [rel gen_nl_code]
    mov ecx, gen_nl_len
    call emit_seq
    ret

gen_entry_p1:
    db 0x48, 0x83, 0xE4, 0xF0           ; and rsp, -16
    db 0xB9, 0xE9, 0xFD, 0x00, 0x00     ; mov ecx, 65001
    db 0x48, 0xB8
    dq GEN_SetConsoleOutputCP
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
    db 0xB9, 0xE9, 0xFD, 0x00, 0x00     ; mov ecx, 65001
    db 0x48, 0xB8
    dq GEN_SetConsoleCP
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
gen_entry_p1_len equ ($ - gen_entry_p1)

gen_entry_p2:
    db 0x89, 0xC1                       ; mov ecx, eax
    db 0x48, 0xB8
    dq GEN_ExitProcess
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0                       ; ExitProcess(main_rax)
gen_entry_p2_len equ ($ - gen_entry_p2)

; --- runtime-помощники генерируемой программы (статические блобы) ------------

gen_ps_code:
    db 0x55                             ; push rbp
    db 0x48, 0x89, 0xE5                 ; mov rbp, rsp
    db 0x48, 0x83, 0xEC, 0x30           ; sub rsp, 0x30
    db 0x48, 0x89, 0x4D, 0xF8           ; mov [rbp-8], rcx   (ptr)
    db 0x48, 0x89, 0x55, 0xF0           ; mov [rbp-16], rdx  (len)
    db 0xB9, 0xF5, 0xFF, 0xFF, 0xFF     ; mov ecx, -11
    db 0x48, 0xB8
    dq GEN_GetStdHandle
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
    db 0x48, 0x89, 0xC1                 ; mov rcx, rax
    db 0x48, 0x8B, 0x55, 0xF8           ; mov rdx, [rbp-8]   (ptr)
    db 0x4C, 0x8B, 0x45, 0xF0           ; mov r8, [rbp-16]   (len)
    db 0x48, 0xC7, 0x45, 0xE8, 0, 0, 0, 0   ; mov qword [rbp-24], 0
    db 0x4C, 0x8D, 0x4D, 0xE8           ; lea r9, [rbp-24]
    db 0x48, 0xC7, 0x44, 0x24, 0x20, 0, 0, 0, 0
    db 0x48, 0xB8
    dq GEN_WriteFile
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
    db 0x48, 0x89, 0xEC                 ; mov rsp, rbp
    db 0x5D                             ; pop rbp
    db 0xC3                             ; ret
gen_ps_len equ ($ - gen_ps_code)

gen_pi_code:
    db 0x55                             ; push rbp
    db 0x48, 0x89, 0xE5                 ; mov rbp, rsp
    db 0x48, 0x83, 0xEC, 0x60           ; sub rsp, 0x60
    db 0x48, 0x89, 0x4D, 0xF8           ; mov [rbp-8], rcx   (значение)
    db 0xB9, 0xF5, 0xFF, 0xFF, 0xFF     ; mov ecx, -11
    db 0x48, 0xB8
    dq GEN_GetStdHandle
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
    db 0x48, 0x89, 0x45, 0xF0           ; mov [rbp-16], rax  (хендл)
    db 0x48, 0x8B, 0x45, 0xF8           ; mov rax, значение
    db 0x45, 0x31, 0xD2                 ; xor r10d, r10d
    db 0x48, 0x85, 0xC0                 ; test rax, rax
.pi_jns: db 0x79, (.pi_pos - .pi_jns - 2)
    db 0x48, 0xF7, 0xD8                 ; neg rax
    db 0x41, 0xBA, 0x01, 0x00, 0x00, 0x00   ; mov r10d, 1
.pi_pos:
    db 0x4C, 0x8D, 0x4D, 0xB8           ; lea r9, [rbp-0x48]
    db 0x45, 0x31, 0xDB                 ; xor r11d, r11d
    db 0x49, 0xC7, 0xC0, 0x0A, 0, 0, 0  ; mov r8, 10
.pi_digit:
    db 0x48, 0x31, 0xD2                 ; xor rdx, rdx
    db 0x49, 0xF7, 0xF0                 ; div r8
    db 0x80, 0xC2, 0x30                 ; add dl, '0'
    db 0x49, 0xFF, 0xC9                 ; dec r9
    db 0x41, 0x88, 0x11                 ; mov [r9], dl
    db 0x49, 0xFF, 0xC3                 ; inc r11
    db 0x48, 0x85, 0xC0                 ; test rax, rax
.pi_jnz: db 0x75, (.pi_digit - .pi_after_jnz)
.pi_after_jnz:
    db 0x45, 0x85, 0xD2                 ; test r10d, r10d
.pi_jz: db 0x74, (.pi_w - .pi_jz - 2)
    db 0x49, 0xFF, 0xC9                 ; dec r9
    db 0x41, 0xC6, 0x01, 0x2D           ; mov byte [r9], '-'
    db 0x49, 0xFF, 0xC3                 ; inc r11
.pi_w:
    db 0x48, 0x8B, 0x4D, 0xF0           ; mov rcx, [rbp-16]
    db 0x4C, 0x89, 0xCA                 ; mov rdx, r9
    db 0x4D, 0x89, 0xD8                 ; mov r8, r11 (длина)
    db 0x4C, 0x8D, 0x4D, 0xE8           ; lea r9, [rbp-24]
    db 0x48, 0xC7, 0x45, 0xE8, 0, 0, 0, 0
    db 0x48, 0xC7, 0x44, 0x24, 0x20, 0, 0, 0, 0
    db 0x48, 0xB8
    dq GEN_WriteFile
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
    db 0x48, 0x89, 0xEC
    db 0x5D
    db 0xC3
gen_pi_len equ ($ - gen_pi_code)

gen_nl_code:
    db 0x55
    db 0x48, 0x89, 0xE5
    db 0x48, 0x83, 0xEC, 0x30
    db 0xB9, 0xF5, 0xFF, 0xFF, 0xFF     ; mov ecx, -11
    db 0x48, 0xB8
    dq GEN_GetStdHandle
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
    db 0x48, 0x89, 0xC1                 ; mov rcx, rax
    db 0x48, 0xBA
    dq (G_IMG + 0x1000 + GEN_NL_OFF)    ; rdx = "\r\n"
    db 0x41, 0xB8, 0x02, 0x00, 0x00, 0x00   ; mov r8d, 2
    db 0x48, 0xC7, 0x45, 0xE8, 0, 0, 0, 0
    db 0x4C, 0x8D, 0x4D, 0xE8
    db 0x48, 0xC7, 0x44, 0x24, 0x20, 0, 0, 0, 0
    db 0x48, 0xB8
    dq GEN_WriteFile
    db 0x48, 0x8B, 0x00
    db 0xFF, 0xD0
    db 0x48, 0x89, 0xEC
    db 0x5D
    db 0xC3
gen_nl_len equ ($ - gen_nl_code)

; ---------------------------------------------------------------------------
; cg_emit_func: rdi = узел функции, eax = метка
; ---------------------------------------------------------------------------
cg_emit_func:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    mov r15, rdi                     ; узел функции
    mov ecx, eax
    call bind_label
    ; пролог: push rbp; mov rbp, rsp; sub rsp, frame
    EMIT 0x55
    EMIT 0x48, 0x89, 0xE5
    mov ecx, [r15 + N_G]             ; следующий свободный слот
    dec ecx
    jle .cf_noframe
    mov eax, ecx
    shl eax, 3                       ; 8*слотов
    add eax, 15
    and eax, ~15                     ; выравнивание 16
    push rax
    EMIT 0x48, 0x81, 0xEC
    pop rax
    call emit_eax_dword
.cf_noframe:
    ; копии параметров: arg i лежит в [rbp + 16 + 8*(n-1-i)] -> слот i+1
    mov rsi, [r15 + N_C]             ; голова параметров
    mov ecx, [r15 + N_D]             ; n
    xor r12d, r12d                   ; i
.cf_ploop:
    cmp rsi, 0
    je .cf_pdone
    cmp r12d, ecx
    jge .cf_pdone
    mov eax, ecx
    dec eax
    sub eax, r12d
    shl eax, 3
    add eax, 16                      ; [rbp + disp]
    push rax
    EMIT 0x48, 0x8B, 0x85            ; mov rax, [rbp+disp]
    pop rax
    call emit_eax_dword
    lea eax, [r12 + 1]
    call cg_store_slot               ; в слот (i+1)
    mov rsi, [rsi + N_NEXT]
    inc r12
    jmp .cf_ploop
.cf_pdone:
    ; тело
    mov rdi, [r15 + N_E]
    call cg_emit_block
    ; неявный return 0
    EMIT 0x31, 0xC0                  ; xor eax, eax
    EMIT 0x48, 0x89, 0xEC            ; mov rsp, rbp
    EMIT 0x5D                        ; pop rbp
    EMIT 0xC3                        ; ret
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; cg_emit_block: rdi = блок (0 допустимо)
; ---------------------------------------------------------------------------
cg_emit_block:
    push rbx
    push rsi
    push rdi
    cmp rdi, 0
    je .ceb_done
    mov rsi, [rdi + N_A]
.ceb_loop:
    cmp rsi, 0
    je .ceb_done
    mov rdi, rsi
    call cg_emit_stmt
    mov rsi, [rsi + N_NEXT]
    jmp .ceb_loop
.ceb_done:
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; cg_emit_stmt: rdi = оператор
; ---------------------------------------------------------------------------
cg_emit_stmt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    mov r14, rdi
    mov eax, [rdi + N_KIND]
    cmp eax, NODE_LET
    je .cs_let
    cmp eax, NODE_ASSIGN
    je .cs_assign
    cmp eax, NODE_IF
    je .cs_if
    cmp eax, NODE_WHILE
    je .cs_while
    cmp eax, NODE_FOR
    je .cs_for
    cmp eax, NODE_RETURN
    je .cs_return
    cmp eax, NODE_EXPRSTMT
    je .cs_exprst
    jmp .cs_done
.cs_let:
    mov eax, [r14 + N_D]             ; тип
    cmp eax, TY_STR
    jne .cs_let_int
    ; строковая переменная: инициализация литералом (проверено в sema)
    mov rsi, [r14 + N_C]
    cmp rsi, 0
    je .cs_let_str0
    cmp qword [rsi + N_KIND], NODE_ESTR
    jne .cs_let_str0
    mov r8, [rsi + N_A]
    mov r9, [rsi + N_B]
    call cg_add_string               ; eax = смещение
    mov r11, G_IMG + 0x1000
    add rax, r11                     ; абсолютный адрес
    EMIT 0x48, 0xB8                  ; mov rax, imm64
    call emit_rax_qword
    mov eax, [r14 + N_F]
    call cg_store_slot
    ; длина во второй слот: берём из сохранённого r9 —
    ; rsi уже испорчен вызовами выше
    mov eax, [r14 + N_F]
    inc eax
    push rax
    mov ecx, r9d
    pop rax
    call cg_mov_mem_imm32
    jmp .cs_done
.cs_let_str0:
    ; без инициализации: оба слота 0
    mov eax, [r14 + N_F]
    xor ecx, ecx
    call cg_mov_mem_imm32
    mov eax, [r14 + N_F]
    inc eax
    xor ecx, ecx
    call cg_mov_mem_imm32
    jmp .cs_done
.cs_let_int:
    mov rsi, [r14 + N_C]
    cmp rsi, 0
    jne .cs_let_expr
    mov eax, [r14 + N_F]
    xor ecx, ecx
    call cg_mov_mem_imm32
    jmp .cs_done
.cs_let_expr:
    mov rdi, rsi
    call cg_emit_expr
    mov eax, [r14 + N_F]
    call cg_store_slot
    jmp .cs_done
.cs_assign:
    mov rsi, [r14 + N_C]             ; выражение
    cmp rsi, 0
    je .cs_done
    cmp qword [rsi + N_KIND], NODE_ESTR
    jne .cs_as_int
    ; строковая переменная <- литерал
    mov r8, [rsi + N_A]
    mov r9, [rsi + N_B]
    call cg_add_string
    mov r11, G_IMG + 0x1000
    add rax, r11
    EMIT 0x48, 0xB8
    call emit_rax_qword
    mov eax, [r14 + N_F]
    call cg_store_slot
    mov eax, [r14 + N_F]
    inc eax
    push rax
    mov ecx, r9d                     ; длина из сохранённого r9 (rsi испорчен)
    pop rax
    call cg_mov_mem_imm32
    jmp .cs_done
.cs_as_int:
    mov rdi, rsi
    call cg_emit_expr
    mov eax, [r14 + N_F]
    call cg_store_slot
    jmp .cs_done
.cs_if:
    mov rdi, [r14 + N_A]
    call cg_emit_expr
    EMIT 0x48, 0x85, 0xC0            ; test rax, rax
    call new_label
    mov r12, rax                     ; L_else/end
    mov ecx, eax
    call cg_jz_label
    mov rdi, [r14 + N_B]
    call cg_emit_block
    cmp qword [r14 + N_C], 0
    je .cs_if_noelse
    call new_label
    mov r13, rax                     ; L_end
    mov ecx, eax
    push rcx                         ; EMIT портит rcx
    EMIT 0xE9
    pop rcx
    call cg_add_fixup
    mov ecx, r12d
    call bind_label
    mov rdi, [r14 + N_C]
    call cg_emit_block
    mov ecx, r13d
    call bind_label
    jmp .cs_done
.cs_if_noelse:
    mov ecx, r12d
    call bind_label
    jmp .cs_done
.cs_while:
    call new_label
    mov r12, rax                     ; L_top
    call new_label
    mov r13, rax                     ; L_end
    mov ecx, r12d
    call bind_label
    mov rdi, [r14 + N_A]
    call cg_emit_expr
    EMIT 0x48, 0x85, 0xC0
    mov ecx, r13d
    call cg_jz_label
    mov rdi, [r14 + N_B]
    call cg_emit_block
    mov ecx, r12d
    call cg_jmp_label
    mov ecx, r13d
    call bind_label
    jmp .cs_done
.cs_for:
    ; слоты: переменная = [N_F], конец = [N_F]+1
    mov rdi, [r14 + N_C]             ; start
    call cg_emit_expr
    mov eax, [r14 + N_F]
    call cg_store_slot
    mov rdi, [r14 + N_D]             ; end
    call cg_emit_expr
    mov eax, [r14 + N_F]
    inc eax
    call cg_store_slot
    call new_label
    mov r12, rax                     ; L_top
    call new_label
    mov r13, rax                     ; L_end
    mov ecx, r12d
    call bind_label
    mov eax, [r14 + N_F]
    call cg_load_slot
    ; cmp rax, [rbp-8*(slot+1)]
    EMIT 0x48, 0x3B, 0x85
    mov eax, [r14 + N_F]
    inc eax
    shl eax, 3
    neg eax                          ; -(8*slot)
    call emit_eax_dword
    mov ecx, r13d
    call cg_jge_label                ; i >= end -> выход
    mov rdi, [r14 + N_E]
    call cg_emit_block
    mov eax, [r14 + N_F]
    call cg_inc_slot
    mov ecx, r12d
    call cg_jmp_label
    mov ecx, r13d
    call bind_label
    jmp .cs_done
.cs_return:
    cmp qword [r14 + N_A], 0
    je .cs_ret0
    mov rdi, [r14 + N_A]
    call cg_emit_expr
    jmp .cs_retep
.cs_ret0:
    EMIT 0x31, 0xC0                  ; xor eax, eax
.cs_retep:
    EMIT 0x48, 0x89, 0xEC
    EMIT 0x5D
    EMIT 0xC3
    jmp .cs_done
.cs_exprst:
    mov rdi, [r14 + N_A]
    call cg_emit_expr
.cs_done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
; cg_emit_expr: rdi = выражение -> эмит кода, результат в rax
; ---------------------------------------------------------------------------
cg_emit_expr:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    cmp rdi, 0
    jne .ce_real
    EMIT 0x31, 0xC0
    jmp .ce_done
.ce_real:
    mov r14, rdi
    mov eax, [rdi + N_KIND]
    cmp eax, NODE_EINT
    je .ce_int
    cmp eax, NODE_ESTR
    je .ce_str
    cmp eax, NODE_EBOOL
    je .ce_bool
    cmp eax, NODE_EIDENT
    je .ce_ident
    cmp eax, NODE_EBIN
    je .ce_bin
    cmp eax, NODE_EUN
    je .ce_un
    cmp eax, NODE_ECALL
    je .ce_call
    EMIT 0x31, 0xC0
    jmp .ce_done
.ce_int:
    mov rax, [r14 + N_A]
    cmp rax, 0x7FFFFFFF
    jg .ce_int_big
    cmp rax, -0x80000000
    jl .ce_int_big
    EMIT 0x48, 0xC7, 0xC0            ; mov rax, imm32 (sign-ext)
    call emit_eax_dword
    jmp .ce_done
.ce_int_big:
    EMIT 0x48, 0xB8
    call emit_rax_qword
    jmp .ce_done
.ce_str:
    mov r8, [r14 + N_A]
    mov r9, [r14 + N_B]
    call cg_add_string
    mov r11, G_IMG + 0x1000
    add rax, r11
    EMIT 0x48, 0xB8
    call emit_rax_qword
    jmp .ce_done
.ce_bool:
    mov eax, [r14 + N_A]
    EMIT 0xB8                        ; mov eax, imm32
    call emit_eax_dword
    jmp .ce_done
.ce_ident:
    mov eax, [r14 + N_F]
    call cg_load_slot
    jmp .ce_done
.ce_bin:
    mov rdi, [r14 + N_B]
    call cg_emit_expr
    EMIT 0x50                        ; push rax (левое)
    mov rdi, [r14 + N_C]
    call cg_emit_expr
    EMIT 0x48, 0x89, 0xC1            ; mov rcx, rax (правое)
    EMIT 0x58                        ; pop rax  (левое)
    mov eax, [r14 + N_A]
    cmp eax, OP_ADD
    je .ce_add
    cmp eax, OP_SUB
    je .ce_sub
    cmp eax, OP_MUL
    je .ce_mul
    cmp eax, OP_DIV
    je .ce_div
    cmp eax, OP_MOD
    je .ce_mod
    cmp eax, OP_EQ
    je .ce_eq
    cmp eax, OP_NE
    je .ce_ne
    cmp eax, OP_LT
    je .ce_lt
    cmp eax, OP_GT
    je .ce_gt
    cmp eax, OP_LE
    je .ce_le
    cmp eax, OP_GE
    je .ce_ge
    cmp eax, OP_AND
    je .ce_and
    cmp eax, OP_OR
    je .ce_or
    jmp .ce_done
.ce_add:
    EMIT 0x48, 0x01, 0xC8            ; add rax, rcx
    jmp .ce_done
.ce_sub:
    EMIT 0x48, 0x29, 0xC8            ; sub rax, rcx
    jmp .ce_done
.ce_mul:
    EMIT 0x48, 0x0F, 0xAF, 0xC1      ; imul rax, rcx
    jmp .ce_done
.ce_div:
    EMIT 0x48, 0x99                  ; cqo
    EMIT 0x48, 0xF7, 0xF9            ; idiv rcx
    jmp .ce_done
.ce_mod:
    EMIT 0x48, 0x99
    EMIT 0x48, 0xF7, 0xF9
    EMIT 0x48, 0x89, 0xD0            ; mov rax, rdx
    jmp .ce_done
.ce_eq:
    EMIT 0x48, 0x39, 0xC8            ; cmp rax, rcx
    EMIT 0x0F, 0x94, 0xC0            ; sete al
    EMIT 0x0F, 0xB6, 0xC0            ; movzx eax, al
    jmp .ce_done
.ce_ne:
    EMIT 0x48, 0x39, 0xC8
    EMIT 0x0F, 0x95, 0xC0
    EMIT 0x0F, 0xB6, 0xC0
    jmp .ce_done
.ce_lt:
    EMIT 0x48, 0x39, 0xC8
    EMIT 0x0F, 0x9C, 0xC0
    EMIT 0x0F, 0xB6, 0xC0
    jmp .ce_done
.ce_gt:
    EMIT 0x48, 0x39, 0xC8
    EMIT 0x0F, 0x9F, 0xC0
    EMIT 0x0F, 0xB6, 0xC0
    jmp .ce_done
.ce_le:
    EMIT 0x48, 0x39, 0xC8
    EMIT 0x0F, 0x9E, 0xC0
    EMIT 0x0F, 0xB6, 0xC0
    jmp .ce_done
.ce_ge:
    EMIT 0x48, 0x39, 0xC8
    EMIT 0x0F, 0x9D, 0xC0
    EMIT 0x0F, 0xB6, 0xC0
    jmp .ce_done
.ce_and:
    EMIT 0x21, 0xC8                  ; and eax, ecx
    jmp .ce_done
.ce_or:
    EMIT 0x09, 0xC8                  ; or eax, ecx
    jmp .ce_done
.ce_un:
    mov rdi, [r14 + N_B]
    call cg_emit_expr
    cmp qword [r14 + N_A], OP_NOT
    je .ce_not
    EMIT 0x48, 0xF7, 0xD8            ; neg rax
    jmp .ce_done
.ce_not:
    EMIT 0x48, 0x85, 0xC0            ; test rax, rax
    EMIT 0x0F, 0x94, 0xC0            ; sete al
    EMIT 0x0F, 0xB6, 0xC0
    jmp .ce_done
.ce_call:
    cmp qword [r14 + N_E], 1
    je .ce_intr
    ; обычная функция
    cmp qword [r14 + N_F], -1
    jne .ce_call_ok
    EMIT 0x31, 0xC0
    jmp .ce_done
.ce_call_ok:
    ; сначала считаем аргументы — выравнивающий пуш должен ЛЕЧЬ ПЕРЕД ними,
    ; чтобы arg_0 оказался в [rbp+16] вызванной функции
    mov rsi, [r14 + N_D]
    xor r12, r12
.ce_cntloop:
    cmp rsi, 0
    je .ce_cntdone
    inc r12
    mov rsi, [rsi + N_NEXT]
    jmp .ce_cntloop
.ce_cntdone:
    mov eax, r12d
    and eax, 1
    jz .ce_nopad
    EMIT 0x31, 0xC0
    EMIT 0x50                        ; выравнивающий пуш (под аргументами)
    inc r12
.ce_nopad:
    mov rsi, [r14 + N_D]             ; аргументы
.ce_argloop:
    cmp rsi, 0
    je .ce_argdone
    mov rdi, rsi
    mov r13, [rsi + N_NEXT]          ; следующий аргумент: EMIT портит rsi
    call cg_emit_expr
    EMIT 0x50                        ; push rax
    mov rsi, r13
    jmp .ce_argloop
.ce_argdone:
    mov eax, [r14 + N_F]
    add eax, LAB_FUNC_BASE
    mov ecx, eax
    call cg_call_label
    mov eax, r12d
    shl eax, 3
    EMIT 0x48, 0x81, 0xC4            ; add rsp, 8*k
    call emit_eax_dword
    jmp .ce_done
.ce_intr:
    ; print/println
    mov r13d, 0                      ; 1 = println
    cmp qword [r14 + N_B], 7
    jne .ce_intr_p
    mov r13d, 1
.ce_intr_p:
    cmp qword [r14 + N_C], 0
    jne .ce_intr_arg
    cmp r13d, 1
    jne .ce_done
    mov ecx, LAB_NEWLINE
    call cg_call_label
    jmp .ce_done
.ce_intr_arg:
    mov rsi, [r14 + N_D]             ; единственный аргумент
    cmp qword [rsi + N_KIND], NODE_ESTR
    jne .ce_intr_nlit
    mov r8, [rsi + N_A]
    mov r9, [rsi + N_B]
    call cg_add_string
    mov r11, G_IMG + 0x1000
    add rax, r11
    push rax
    EMIT 0x48, 0xB9                  ; mov rcx, imm64
    pop rax
    call emit_rax_qword
    EMIT 0xBA                        ; mov edx, imm32
    mov eax, r9d                     ; длина (r9 сохранён cg_add_string)
    call emit_eax_dword
    mov ecx, LAB_PRINTSTR
    call cg_call_label
    jmp .ce_intr_nl
.ce_intr_nlit:
    cmp qword [rsi + N_KIND], NODE_EIDENT
    jne .ce_intr_int
    cmp qword [rsi + N_D], TY_STR
    jne .ce_intr_int
    ; строковая переменная: два слота (ptr, len); слот кэшируем в r15 —
    ; EMIT/emit_seq портят rsi
    mov r15d, [rsi + N_F]
    mov eax, r15d
    push rax
    EMIT 0x48, 0x8B, 0x8D            ; mov rcx, [rbp-8*s]
    pop rax
    shl eax, 3
    neg eax                          ; -(8*slot)
    call emit_eax_dword
    lea eax, [r15 + 1]
    push rax
    EMIT 0x48, 0x8B, 0x95            ; mov rdx, [rbp-8*(s+1)]
    pop rax
    shl eax, 3
    neg eax                          ; -(8*slot)
    call emit_eax_dword
    mov ecx, LAB_PRINTSTR
    call cg_call_label
    jmp .ce_intr_nl
.ce_intr_int:
    mov rdi, rsi
    call cg_emit_expr
    EMIT 0x48, 0x89, 0xC1            ; mov rcx, rax
    mov ecx, LAB_PRINTINT
    call cg_call_label
.ce_intr_nl:
    cmp r13d, 1
    jne .ce_done
    mov ecx, LAB_NEWLINE
    call cg_call_label
    jmp .ce_done
.ce_done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; =============================================================================
; СБОРКА PE генерируемой программы
; =============================================================================
build_pe:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    ; длины
    mov r12, [rbx + G_CODECUR]
    sub r12, [rbx + G_CODE]          ; code_len
    mov r13, [rbx + G_RDATACUR]
    sub r13, [rbx + G_RDATA]         ; rdata_len
    ; text_rva
    mov eax, r13d
    add eax, 0xFFF
    and eax, ~0xFFF
    add eax, 0x1000
    mov r14d, eax                    ; text_rva
    ; text_raw / rdata_raw / text_raw_off / total
    mov ecx, r12d
    add ecx, 0x1FF
    and ecx, ~0x1FF                  ; text_raw
    mov r10d, ecx
    mov eax, r13d
    add eax, 0x1FF
    and eax, ~0x1FF                  ; rdata_raw
    mov r11d, eax
    lea eax, [rax + 0x200]           ; text_raw_off
    mov r8d, eax
    add eax, r10d                    ; total
    mov r9d, eax
    ; проверка вместимости
    mov rsi, [rbx + G_OUT]
    mov rdx, [rbx + G_OUTEND]
    sub rdx, rsi
    cmp rax, rdx
    jle .bp_ok
    mov rdx, VA_RDATA(msg_out_of_mem)
    mov r8, 13
    call fatal_err
.bp_ok:
    ; обнулить файл
    mov rdi, rsi
    mov ecx, r9d
    xor eax, eax
.bp_zero:
    mov [rdi], al
    inc rdi
    dec ecx
    jnz .bp_zero
    ; --- заголовки ---
    mov r15, [rbx + G_OUT]
    mov byte [r15 + 0], 'M'
    mov byte [r15 + 1], 'Z'
    mov dword [r15 + 0x3C], 0x80
    mov dword [r15 + 0x80], 0x00004550
    mov word [r15 + 0x84], 0x8664
    mov word [r15 + 0x86], 2
    mov word [r15 + 0x94], 240
    mov word [r15 + 0x96], 0x0022
    mov word [r15 + 0x98], 0x020B
    mov byte [r15 + 0x9A], 14
    mov dword [r15 + 0x9C], r10d     ; SizeOfCode
    mov dword [r15 + 0xA0], r11d     ; SizeOfInitializedData
    mov dword [r15 + 0xA8], r14d     ; AddressOfEntryPoint (offset 0 в .text)
    mov dword [r15 + 0xAC], r14d     ; BaseOfCode
    mov rax, G_IMG
    mov qword [r15 + 0xB0], rax
    mov dword [r15 + 0xB8], 0x1000
    mov dword [r15 + 0xBC], 0x200
    mov word [r15 + 0xC0], 6
    mov word [r15 + 0xC8], 6
    mov eax, r12d                    ; SizeOfImage = text_rva + align(code,4K)
    add eax, 0xFFF
    and eax, ~0xFFF
    add eax, r14d
    mov dword [r15 + 0xD0], eax
    mov dword [r15 + 0xD4], 0x200    ; SizeOfHeaders
    mov word [r15 + 0xDC], 3         ; subsystem console
    mov word [r15 + 0xDE], 0         ; DllCharacteristics: без ASLR
    mov qword [r15 + 0xE0], 0x100000
    mov qword [r15 + 0xE8], 0x1000
    mov qword [r15 + 0xF0], 0x100000
    mov qword [r15 + 0xF8], 0x1000
    mov dword [r15 + 0x104], 16      ; NumberOfRvaAndSizes
    ; каталоги: [1]=import, [12]=IAT
    mov dword [r15 + 0x110], 0x1000
    mov dword [r15 + 0x114], 40
    mov dword [r15 + 0x168], 0x10B8  ; IAT RVA (rdata_off 0xB8)
    mov dword [r15 + 0x16C], 0x28
    ; секция .rdata (заголовок 0x188)
    mov dword [r15 + 0x188], 0x6164722E   ; ".rda" (2E 72 64 61)
    mov dword [r15 + 0x18C], 0x00006174    ; "ta\0\0" (74 61 00 00)
    mov dword [r15 + 0x190], r13d          ; VirtualSize
    mov dword [r15 + 0x194], 0x1000
    mov dword [r15 + 0x198], r11d          ; SizeOfRawData
    mov dword [r15 + 0x19C], 0x200         ; PointerToRawData
    mov dword [r15 + 0x1AC], 0x40000040   ; Characteristics (CNT_INIT_DATA|MEM_READ)
    ; секция .text (заголовок 0x1B0)
    mov dword [r15 + 0x1B0], 0x7865742E    ; ".tex" (2E 74 65 78)
    mov dword [r15 + 0x1B4], 0x00000074    ; "t\0\0\0"
    mov dword [r15 + 0x1B8], r12d          ; VirtualSize
    mov dword [r15 + 0x1BC], r14d          ; VirtualAddress
    mov dword [r15 + 0x1C0], r10d          ; SizeOfRawData
    mov dword [r15 + 0x1C4], r8d           ; PointerToRawData
    mov dword [r15 + 0x1D4], 0x60000020   ; Characteristics (CNT_CODE|MEM_EXEC|MEM_READ)
    ; --- данные ---
    ; .rdata в файл 0x200
    mov rdi, [rbx + G_OUT]
    add rdi, 0x200
    mov rsi, [rbx + G_RDATA]
    mov rcx, r13
.bp_rd:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .bp_rd
    ; код в файл text_raw_off
    mov rdi, [rbx + G_OUT]
    add rdi, r8
    mov rsi, [rbx + G_CODE]
    mov rcx, r12
.bp_tx:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .bp_tx
    mov [rbx + G_OUTLEN], r9
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------------------------------------------------------------------------
write_output:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 0x40
    mov rcx, [rbx + G_OUTPATH]
    mov rdx, 0x40000000              ; GENERIC_WRITE
    xor r8, r8
    xor r9, r9
    mov qword [rsp + 0x20], 2        ; CREATE_ALWAYS
    mov qword [rsp + 0x28], 0x80     ; FILE_ATTRIBUTE_NORMAL
    mov qword [rsp + 0x30], 0
    API COMP_CreateFileA
    cmp rax, -1
    je .wo_fail
    mov r12, rax
    mov rsi, [rbx + G_OUT]
    mov r13, [rbx + G_OUTLEN]
.wo_loop:
    cmp r13, 0
    je .wo_written
    mov r8, r13
    cmp r8, 0x100000
    jle .wo_chunk_ok
    mov r8, 0x100000
.wo_chunk_ok:
    mov rcx, r12
    mov rdx, rsi
    lea r9, [rsp + 0x28]
    mov qword [rsp + 0x20], 0
    mov qword [rsp + 0x28], 0
    push rsi
    push r8
    push r13
    API COMP_WriteFile
    pop r13
    pop r8
    pop rsi
    add rsi, r8
    sub r13, r8
    jmp .wo_loop
.wo_written:
    mov rcx, r12
    API COMP_CloseHandle
    add rsp, 0x40
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
.wo_fail:
    mov rdx, VA_RDATA(msg_cant_write)
    mov r8, 19
    call fatal_err

; ---------------------------------------------------------------------------
; блоб импорта генерируемой программы (0xE8) + "\r\n" (итого 0xEA)
; ---------------------------------------------------------------------------
gen_import_blob:
    db 0x88, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0x10, 0x00, 0x00
    db 0xb8, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4b, 0x45, 0x52, 0x4e, 0x45, 0x4c, 0x33, 0x32
    db 0x2e, 0x44, 0x4c, 0x4c, 0x00, 0x00, 0x00, 0x00, 0x47, 0x65, 0x74, 0x53, 0x74, 0x64, 0x48, 0x61
    db 0x6e, 0x64, 0x6c, 0x65, 0x00, 0x00, 0x00, 0x00, 0x57, 0x72, 0x69, 0x74, 0x65, 0x46, 0x69, 0x6c
    db 0x65, 0x00, 0x00, 0x00, 0x45, 0x78, 0x69, 0x74, 0x50, 0x72, 0x6f, 0x63, 0x65, 0x73, 0x73, 0x00
    db 0x00, 0x00, 0x53, 0x65, 0x74, 0x43, 0x6f, 0x6e, 0x73, 0x6f, 0x6c, 0x65, 0x4f, 0x75, 0x74, 0x70
    db 0x75, 0x74, 0x43, 0x50, 0x00, 0x00, 0x00, 0x00, 0x53, 0x65, 0x74, 0x43, 0x6f, 0x6e, 0x73, 0x6f
    db 0x6c, 0x65, 0x43, 0x50, 0x00, 0x00, 0x00, 0x00, 0x36, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x46, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x52, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x60, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 13, 10                        ; "\r\n" — смещение GEN_NL_OFF
gen_blob_len equ ($ - gen_import_blob)

text_end:
    times (TEXT_RAW - TEXT_VSIZE) db 0   ; pad .text raw data up to SizeOfRawData
