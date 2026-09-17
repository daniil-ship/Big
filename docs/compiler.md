# Компилятор Big — как это работает

> Один пайплайн — два бэкенда (PE64 / ELF64), один исходник логики (`bigc.py` ↔ `src/bigc.asm`).

## Обзор

```
source.bg
   │
   ▼
 ┌─────┐   DFA, Span(line,col,text)   ┌──────┐
 │ LEX │ ───────────────────────────► │Tokens│
 └──┬──┘                              └──────┘
    │ диагностикa E10xx/W10xx
    ▼
 ┌──────┐  рекурсивный спуск + Pratt   ┌─────┐
 │PARSE │ ───────────────────────────► │ AST │ Program{ funcs, consts, uses }
 └──┬──┘                               └─────┘
    │ E20xx/W20xx
    ▼
 ┌──────┐  Scope, infer, check         ┌──────────┐
 │ SEMA │ ───────────────────────────► │Diagnostics│ E30xx/W30xx/I30xx
 └──┬──┘                               └──────────┘
    │ IR (stack-машина, Big IR)
    ▼
 ┌─────┐  constant folding, DCE        ┌─────┐
 │ OPT │ ───────────────────────────► │  IR │
 └──┬──┘                               └─────┘
    ▼
 ┌─────┐  прямая эмиссия x86-64        ┌───────┐
 │ CG  │ ───────────────────────────► │ .text │ bytes + fixups + .rdata strings
 └──┬──┘                               └───────┘
    │ PEBuilder / ELFBuilder (ручной заголовок)
    ▼
  PE64 / ELF64  (без линкера)
```

Цвета: `LEX` голубой, `PARSE` фиолетовый, `SEMA` жёлтый, `CG` зелёный — в логах `bigc.py --lex/--parse/--sema`.

## 1. LEX — `class Lexer`

- Вход: `src: str, filename: str`
- Состояние: `pos, line, col, tokens, diagnostics`
- Методы: `cur()`, `peek(n)`, `advance(n)`, `make_span()`, `add_token()`, `lex()`

DFA состояния: `S_INIT`, `S_IDENT`, `S_NUMBER`, `S_STRING`, `S_COMMENT` (line/block). Отслеживает `line/col` для каждого токена → `Span(filename, line, col, end_col, line_text)`.

Токены — `TokKind` enum (см. `spec.md`): `KW_FUNC`, `IDENT`, `INT`, `STRING`, `ARROW`, `DOT2` (`..`) и т.д. `EOF` всегда последний.

Диагностика LEX:
- `E1000` неизвестный символ `c (U+XXXX)` + `help: уберите или заэкранируйте`
- `E1001` незакрытая строка
- `E1002` незакрытый `/*`
- `W1003` unknown escape `\x`

## 2. PARSE — `class Parser`

- Вход: `tokens: List[Token], filename, source`
- Выход: `Program(funcs, consts, uses)`
- Техника: рекурсивный спуск для `program/block/stmt`, Pratt (`parse_expr(min_prec)`) для бинарных.

Ключевые методы:
- `parse()` — цикл `func`/`const`/`use`, иначе `E2000`
- `parse_func()` — `func` IDENT `(` params `)` (`->` type)? `block`
- `parse_block()` — `{` stmt* `}`
- `parse_let()` — `let` IDENT `:` type `=` expr `;`? (`W2001` если нет `;`)
- `parse_if/while/for/return/break/continue`
- `parse_expr` / `parse_unary` / `parse_primary` (INT, STRING, `true`/`false`, `IDENT` call, `(expr)`)

Ошибки PARSE:
- `E2000` неожиданный токен в глобальной области
- `E2001/E2003` типы/скобки
- `E2004` имя параметра
- `E2005` `for` без `..`
- `E2006` неожиданный токен в выражении
- `W2001/W2002` пропущена `;`

Восстановление: при ошибке парсер пытается `advance()` до `;`/`}` и продолжает — чтобы собрать больше диагностик за один прогон.

## 3. SEMA — `class Sema`

- Вход: `Program`
- Структуры: `Scope(parent, table:Dict[str,(type,span)]`, `Diagnostic` лист

Этапы:
1. `analyze()` — проходит по `prog.funcs`, проверяет дубли `E3000`, отсутствие `main` `W3000`, пустой файл `E3005`, помечает `I3001` для `main`.
2. `analyze_func(f)` — создаёт `Scope`, декларирует параметры, `analyze_block`.
3. `analyze_block(blk, scope)` — новый `Scope(parent)`, `analyze_stmt` для каждого.
4. `analyze_stmt` — ветвление по `LetStmt/AssignStmt/IfStmt/WhileStmt/ForStmt/ReturnStmt/ExprStmt`
5. `infer_expr(e, scope) -> type|None` — выводит тип:
   - `Literal(i32)` → `i32`, `str` → `str`, `bool` → `bool`
   - `Var` → `resolve` → `E3011` если нет, иначе тип из `declare`
   - `Call(print)` → проверяет `E3012/E3013/E3014`, `W3008` если expr-stmt без эффекта
   - `Binary(a + b)` → `types_compatible`, `W3010/W3009/E3015`
6. `check_unused()` — после блока ищет `declare` без `read` → `W3002`

Типы помогают `CG` — константы уже известны.

## 4. IR / OPT

Сейчас IR — не отдельный байткод, а прямо `AST` + `var_init_map`. `opt_fold` — это `eval_const_int`:

```python
def eval_const_int(e, var_init_map):
    if Literal(INT): return int(value)
    if Var(name): return eval_const_int(var_init_map[name])
    if Binary(left, op, right): return eval(op, eval(left), eval(right))
    if Unary(op, expr): ...
```

Используется в `CG` для:
- сворачивания `let c = a + b*3`
- вывода размера строк для `print`
- проверки `for 0..N` (N должен быть const)

Будущее: MIR-подобная stack-машина, peephole (`add 0` → nop, `imul 1` → nop), DCE.

## 5. CG — `class Emitter` + `PEBuilder` / `ELFBuilder`

### 5.1 Emitter

`Emitter` — буфер `bytearray` + `fixups` + `labels`:

```python
em = Emitter()
em.emit(0x48, 0xB8); em.emit_u64(42)   # mov rax,42
em.emit(0xE8); em.emit_u32(0); em.fixups.append((pos, "print", "rel32"))
```

Методы: `emit(*bytes)`, `emit_u32`, `emit_u64`, `label(name)`, `jmp(label)`, `jmp_if_zero(label)`, `call(label)`, `fixup()`.

Регистры: `rax` — аккумулятор выражений, `rcx/rdx/r8/r9` — аргументы Win x64, `rdi/rsi/rdx` — Linux syscall. Локальные — `[rbp - off]`, `rbx` — индекс цикла.

Для каждой функции:
```
push rbp; mov rbp,rsp; sub rsp, N*8   # пролог, N = locals+temps
… тело: для каждого stmt эмитит код …
leave; ret                            # для не-main
xor ecx,ecx; call [IAT ExitProcess]   # для main (PE)  или  mov rax,60; syscall (ELF)
```

Примеры эмита:
- `let x: i32 = 42` → `mov rax,42; mov [rbp-8],rax`
- `x = y * 2` → `mov rax,[rbp-16]; imul rax,2; mov [rbp-8],rax`
- `if cond {A} else {B}` → `cmp rax,0; je else; A; jmp end; else: B; end:`
- `for i in 0..5 { body }` → `mov rbx,0; loop: cmp rbx,5; jge end; mov [rbp-8],rbx; body; inc rbx; jmp loop; end:`
- `print("hi")` → (см. ниже)

### 5.2 PEBuilder (`bigc.py:PEBuilder`)

Ручная сборка, 1-в-1 как в `src/bigc.asm:pe_build`:

```
offset 0x00: DOS header (MZ, e_lfanew 0x80, 64 байта)
offset 0x80: PE sig "PE\0\0"
offset 0x84: COFF header (Machine 0x8664, Sections 2, TimeDate 0, OptHdr 240, Char 0x022)
offset 0x98: Optional header PE32+ (Magic 0x20B, Entry 0x1000, ImageBase 0x140000000,
          SectionAlign 0x1000, FileAlign 0x200, SizeOfImage ..., Subsystem 3,
          DllCharacteristics 0 (фикс база, без ASLR для детерминизма))
offset ...: Section headers (2×40):
          .text  VirtualSize ..., RVA 0x1000, Raw 0x200, Flags 0x60000020
          .rdata VirtualSize ..., RVA 0x2000, Raw ...,    Flags 0x40000040
offset 0x200: .text (код из Emitter)
pad to FileAlign 0x200
offset ...: .rdata layout:
          0x00 import dir (kernel32.dll descriptor)
          0x28 dll name "KERNEL32.DLL\0"
          0x38 Hint/Name GetStdHandle, WriteFile, ExitProcess
          0x60 INT (OriginalFirstThunk) — RVA на Hint/Name
          0x80 IAT (FirstThunk) — то же, патчится лоадером
          0xA0 strings: каждая строка Big программы, NUL-терминатор + pad
```

Всё выравнивается на `FileAlign 0x200`. Импорт — минимальный, чтобы `wine`/`Windows` загрузили.

Код в `pe_build` использует `struct.pack_into` на `bytearray` (важно: `bytearray`, не `bytes`, иначе `TypeError`).

### 5.3 ELFBuilder (`bigc.py:ELFBuilder`)

```
0x00 EHDR (64 байта): 7F 'ELF' 02 01 01 00 ..., Type 2 (EXEC), Machine 62 (x86-64),
     Entry 0x400000, PHDR off 64, SH off 0, Flags 0, EH 64, PH 56, SH 0
0x40 PHDR (56 байт): Type 1 (PT_LOAD), Flags 5 (R+X), Off 0, Vaddr 0x400000,
     Paddr 0x400000, Filesz ..., Memsz ..., Align 0x1000
0x78 .text (код)
... .rodata (строки)
pad
```

Точка входа — `ELF_BASE 0x400000` (как у `tcc`/`nasm`). Нет `PT_INTERP`, нет `dynamic` — статический бинарь, работает везде. Syscalls:

```
write: rax=1, rdi=1, rsi=ptr, rdx=len, syscall  (0x0F 0x05)
exit:  rax=60, rdi=code, syscall
```

Строки в `.rodata` сразу после кода, адреса считаются `BASE + off`.

## 6. Диагностика — как в Rust

- Структура: `Diagnostic(level, code, message, span, notes, helps)`
- `span`: `file:line:col`, `line_text`, `^~~~` (длина токена)
- `notes`: `= note: …`
- `helps`: `= help: …` (всегда есть, подсказывает фикс)
- Цвета: `RED` для `error`, `YELLOW` `warning`, `CYAN` `info`, `BOLD` для кода
- Печать: `print_diagnostics()` сортирует, группирует по `level`, `has_errors()` решает фейлить ли.

## 7. Bootstrap и asm

- `bigc.py` — эталон, полный пайплайн, тестируется ежедневно.
- `src/bigc.asm` — ручной перевод того же пайплайна на asm, с теми же константами (`IMAGE_BASE`, `SECTION_ALIGN`), теми же эмит-байтами (`48 B8`, `E8`, `E9`, `0F 84` …). Собирается `fasm src/bigc.asm bigc.exe`.
- `src/compiler.bg` — минимальный self-host: `func main() -> i32 { print("Big Compiler …"); return 0; }` — доказывает, что Big может скомпилировать себя; расширяется по мере роста рантайма.

## 8. Производительность

- Нет LLVM, нет объектных файлов, нет линкера — `O(n)` проход по AST → байты.
- `PEBuilder`/`ELFBuilder` — один `bytearray` + `pack_into`, без аллокаций.
- Бинари < 4KB — помещаются в один `PT_LOAD` / две секции, загружаются за одну страницу.
- Замер `time python3 bigc.py examples/main.bg --target linux` — ~20-30ms на Ryzen, из них 80% — Python старт, сам `CG` < 1ms.

## 9. Ограничения и TODO (честные)

| TODO | Где в коде |
|------|------------|
| `print(int)` для не-констант → `itoa` | `CG:print_replacements` сейчас `"<int>"` |
| `else if` без скобок — работает, но без `brace` варнинг | `parse_if` |
| `for` с не-констант N | `parse_for` + `eval_const_int` |
| Массивы/срезы/структуры | `parse_type`, `Sema` |
| Модули `use` резолв | `parse_use` |
| FFI `extern` | `PEBuilder` импорт |
| Дебаг-инфо/DWARF | `ELFBuilder` |

Каждый TODO помечен `W4002` или `TODO` в `CG` — не скрывается.
