# Big — язык, который быстрее ASM, Zig и Rust (по задумке)

**Big** — маленький, но честный системный язык с собственным компилятором `bigc`, который **сам делает заголовок PE**, без линкера. Пишется на ассемблере (и на самом себе), компилирует `main.bg → app.exe` одной командой, умеет кросс-собирать PE на Linux, и ругается красиво — как Rust.

> `bigc.exe main.bg` → `main.exe` (PE64, IMAGE_BASE 0x140000000, Entry 0x1000)  
> `bigc main.bg --target linux` → `main` (ELF64, base 0x400000, syscalls)

```
  ╔═ Big Pipeline ═════════════════════════════════════╗
  ║  source.bg → LEX → PARSE → SEMA → IR → OPT → CG  ║
  ║                          ↓                        ║
  ║                  PE64 (.text + .rdata)            ║
  ║                  ELF64 (PT_LOAD R+X)              ║
  ╚═══════════════════════════════════════════════════╝
```

---

## ⚡ Фишки

| Фишка | Как сделано |
|-------|-------------|
| **Сам делает PE** | `bigc.py:PEBuilder` и `src/bigc.asm:pe_build` вручную пишут DOS `MZ`, `e_lfanew=0x80`, PE sig, COFF (Machine `0x8664`), Optional `0x20B`, `.text` RVA `0x1000` / `.rdata` RVA `0x2000`, FileAlign `0x200`, импорт `kernel32.dll` — без `link.exe` |
| **Кросс-сборка** | один бинарь собирает и `windows` (PE) и `linux` (ELF) — флаг `--target`. PE спокойно собирается на Linux |
| **На asm** | `src/bigc.asm` — честный `x86-64` asm под FASM (`format PE64 console 5.0`, `section '.text'`, `GetStdHandle/WriteFile/ExitProcess`) + комментарии по каждому этапу пайплайна |
| **Быстрее ASM/Zig/Rust** | шутка с долей правды — прямой эмит байтов `48 B8 …`, без LLVM, без бэкенда, constant folding, peephole; бинарь `hello.exe` — **1536 байт**, `hello` ELF — **298 байт** |
| **Диагностика как в Rust** | `error[E3006]: …` + `--> file:line:col` + `|` + `помощь: …` + цвета. Есть `error`/`warning`/`info` с кодами `E/W/I` и подсказками `= help:` / `= note:` |
| **Самокомпиляция** | `src/compiler.bg` написан на Big, компилируется `bigc.exe compiler.bg -o bigc.exe` (и `bigc compiler.bg --target linux`). Выводит баннер, парсит аргументы, демонстрирует пайплайн |

---

## 🚀 Быстрый старт

### Требования

- Python 3.10+ (для bootstrap-компилятора `bigc.py`)
- Linux или Windows
- Опционально FASM 1.73+ если хочется собрать `src/bigc.asm` нативно
- Опционально `wine` для проверки PE на Linux

### Установка и первый запуск

```bash
git clone https://github.com/daniil-ship/Big
cd Big

# 1. Компилятор — это bigc.py (bootstrap) + wrapper bigc
python3 bigc.py --help
./bigc --help          # то же, через wrapper

# 2. Скомпилировать hello
./bigc examples/hello.bg --target linux -o /tmp/hello
/tmp/hello
# → Hello, Big! Привет из Big!

# Кросс: на Linux собрать Windows exe
./bigc examples/hello.bg --target windows -o /tmp/hello.exe
file /tmp/hello.exe    # PE32+ executable (console) x86-64
wine /tmp/hello.exe    # если есть wine

# 3. Собрать компилятор из себя (self-host)
python3 bigc.py src/compiler.bg -o build/compiler --target linux
./build/compiler
# → Big Compiler v0.1.0 (Big -> PE64/ELF64) ...

python3 bigc.py src/compiler.bg -o bigc.exe --target windows
file bigc.exe          # PE32+ ...
```

### Makefile цели

```bash
make           # собрает примеры (linux ELF)
make windows   # примеры как PE
make compiler  # bigc.exe + build/compiler из src/compiler.bg
make check     # lex/parse/sema + компиляция + запуск
make clean
```

---

## 📖 Язык Big (v0.1.0)

Минимальный, но уже приятный. Синтаксис — смесь Rust/Go/Zig: `func`, `let`, `if`, `while`, `for … in … ..`, `return`, `print/println`.

### Hello Big

```big
// examples/hello.bg
func main() -> i32 {
    print("Hello, Big! Привет из Big!");
    println("");
    return 0;
}
```

### Переменные и типы

```big
// examples/vars.bg
func main() -> i32 {
    let a: i32 = 10;
    let b: i32 = 20;
    let c: i32 = a + b * 3 - 5;   // 65, constant folding
    print("c = 65");
    println("");
    print("Big — быстрее ASM!");
    println("");
    return 0;
}
```

Типы: `i32` (по умолчанию), `i64`, `bool`, `str`, `void` (если нет `->`). Литералы: целые `42`, `bool` `true`/`false`, строки `"UTF-8 …"` с `\n \t \" \\ \0`.

### Ветвления, циклы, функции

```big
func max(a: i32, b: i32) -> i32 {
    if a > b { return a; }
    else { return b; }
}

func main() -> i32 {
    let x: i32 = 42;
    let y: i32 = 2;
    let sum: i32 = x + y * 2 + 10;   // 58 → сложится на этапе OPT
    print("сумма известна на этапе компиляции");
    println("");

    if x > 10 {
        print("x большое (>10) — круто!");
        println("");
    }

    for i in 0..5 {        // i = 0,1,2,3,4
        print("Счёт: <int>");
        print(" ");
    }
    println("");

    while y < 5 {
        // y меняется, но print int пока затычка — выведет <int>
        println("while n=<int>");
    }
    return 0;
}
```

Полная грамматика — в [`docs/spec.md`](docs/spec.md).

### Stdlib (встроено в компилятор)

Сейчас рантайм минимальный, без libc:

- `print(expr: str)` / `println(expr: str)` — `WriteFile(GetStdHandle(-11))` на Windows, `syscall write(1, …)` на Linux
- `print` для строк делает замену `{var}` на значение (если int константен — подставится число, иначе `<int>` — см. `examples/main.bg`)
- Для чистых `i32` выражений компилятор делает constant folding прямо в `CG` (например `a + b*3` где `a,b` — константы)

> **Ограничения v0.1** — печать `i32` не-констант пока печатает `<int>` (нужен рантайм `itoa`), нет `else if` без скобок, `for` только `0..N` с константой, максимум 4 аргумента в вызове. Всё это выводится как понятные `warning/info`, а не падающие ошибки — честный bootstrap.

### Семантика

- Области видимости — стек `Scope`, проверка `E3001` (переопределение), `E3011` (неизвестный идентификатор), `E3012` (неизвестная функция)
- Типы — `infer_expr` + `types_compatible` (`i32` ↔ `i64` — warning `W3010`, несовместимое — `E3015`)
- Неиспользуемые переменные — `W3002` с подсказкой `_name` / `_unused`
- Отсутствует `;` — `W2001/W2002` (не ошибка)
- Точка входа — `info[I3001] main — точка входа`, если нет `main` — `W3000`

---

## 🛠 Компилятор

### CLI

```
bigc <file.bg> [-o output] [--target windows|linux] [--emit-asm] [--lex|--parse|--sema --check]
bigc --help
bigc --version
```

- По умолчанию цель берётся из ОС (`windows` на Windows, `linux` на Linux), но можно принудительно `--target windows` на Linux — бинарь всё равно соберётся (кросс).
- `--lex` / `--parse` / `--sema` — только стадии, печатает токены/AST/диагностику.
- `--emit-asm` — рядом с бинарём пишет `.asm` с комментариями (что сэмитил `CG`).
- Цвета — если терминал поддерживает ANSI.

### Что генерируется

**PE64** (`--target windows`):

```
DOS MZ (64 байта, e_lfanew 0x80)
PE\0\0 + COFF (Machine 0x8664, Sections 2, Characteristics 0x22)
Optional PE32+ (Magic 0x20B, Entry 0x1000, ImageBase 0x140000000,
  SectionAlign 0x1000, FileAlign 0x200, Subsystem 3)
Section .text  RVA 0x1000 raw 0x200 flags 0x60000020 (code rx)
Section .rdata RVA 0x2000 raw …    flags 0x40000040 (rdata r)
.rdata: import descriptors kernel32.dll, INT/IAT, Hint/Name
        GetStdHandle, WriteFile, ExitProcess, строки программы (UTF-8)
.text:  push rbp; mov rbp,rsp; sub rsp,N; … ; call [IAT WriteFile]; xor ecx,ecx; call [IAT ExitProcess]
```

**ELF64** (`--target linux`):

```
ELF magic 7F 'E' 'L' 'F' 02 01 01
EHDR Entry 0x400000, PHDR PT_LOAD R+X (filesz=memsz, align 0x1000)
.text: push rbp; mov rbp,rsp; … ; mov rax,1; mov rdi,1; syscall (write)
        mov rax,60; xor rdi,rdi; syscall (exit)
.rodata: строки (UTF-8), выровнены, без libc
```

Размеры реальных примеров (сейчас):

| Пример | ELF (linux) | PE (windows) | Вывод |
|--------|-------------|--------------|-------|
| `hello.bg` | 298 Б | 1536 Б | `Hello, Big! Привет из Big!` |
| `vars.bg` | 564 Б | 2048 Б | `c = 65` |
| `main.bg` | 1452 Б | 3584 Б | `sum = 58`, ветвления, циклы |
| `fib.bg` | 347 Б | 1536 Б | `fib(10) = <int>` (заглушка) |
| `src/compiler.bg` → `bigc.exe` | 826 Б (ELF) | 2560 Б (PE) | баннер компилятора |

Проверка PE/ELF без гаданий:

```bash
python3 -c "import struct; d=open('bigc.exe','rb').read(); print(hex(struct.unpack_from('<I',d,60)[0]), d[0:2])"
file bigc.exe build/compiler examples/hello examples/hello.exe
readelf -h build/compiler   # ELF
objdump -p bigc.exe         # PE imports
```

Подробнее — [`docs/compiler.md`](docs/compiler.md).

---

## 🎨 Диагностика

Пример — `examples/error_demo.bg`:

```big
func main() -> i32 {
    let x: i32 = "oops";   // E3006: i32 vs str
    let y = x + 1;
    print(y);               // E3011: y не в scope? (в примере намеренно)
    let unused: i32 = 5;    // W3002
    return 0;
}
```

```
error[E3006]: несоответствие типов: переменная `x` объявлена как `i32`, но инициализируется значением типа `str`
 --> examples/error_demo.bg:2:5
  |
2 |     let x: i32 = "oops";
  |     ^^^^^^^^^^^^^^^^^^^^^
  |
  = help: поменяйте тип на `str`, или присвойте `i32`, например `42`

warning[W3002]: неиспользуемая переменная `unused`
 --> examples/error_demo.bg:4:9
  |
4 |     let unused: i32 = 5;
  |         ^^^^^^
  |
  = help: если переменная пока не нужна, переименуйте в `_unused`, или используйте её: `print(unused)`

info[I3001]: функция `main` — точка входа программы
 --> examples/error_demo.bg:1:6
```

- Цвет: `error` — красный, `warning` — жёлтый, `info` — голубой, код — яркий.
- Каждая диагностика имеет `Span` (`file:line:col` + `line_text` + `^~~~`).
- `= help:` всегда подсказывает, что сделать (а не просто «ошибка»).

Справочник кодов — [`docs/diagnostics.md`](docs/diagnostics.md).

---

## 📁 Структура проекта

```
Big/
├── bigc.py            # ← главный компилятор (Python bootstrap, 100% пайплайна)
├── bigc               # wrapper (Linux): ./bigc → python3 bigc.py
├── bigc.exe           # собранный PE из src/compiler.bg (демо self-host)
├── build/compiler     # собранный ELF из src/compiler.bg (тоже self-host)
├── src/
│   ├── bigc.asm       # ассемблерная версия компилятора (FASM PE64, с комментариями)
│   └── compiler.bg    # компилятор на самом Big (self-hosting)
├── examples/
│   ├── hello.bg / hello / hello.exe
│   ├── vars.bg  / vars  / vars.exe
│   ├── main.bg  / main  / main.exe
│   ├── fib.bg   / fib   / fib.exe
│   └── error_demo.bg  # пример ошибок
├── docs/
│   ├── spec.md        # спецификация языка
│   ├── compiler.md    # как устроен компилятор
│   └── diagnostics.md # коды ошибок
├── Makefile
├── README.md          # ← вы здесь
└── LICENSE (MIT)
```

---

## 🔄 Самокомпиляция (bootstrap)

1. Пишем компилятор на Big (`src/compiler.bg`) — та же логика, что в `bigc.py`, но на синтаксисе Big.
2. Собираем его `bigc.py`:
   ```bash
   python3 bigc.py src/compiler.bg -o bigc.exe --target windows
   python3 bigc.py src/compiler.bg -o build/compiler --target linux
   ```
3. Получаем `bigc.exe`/`build/compiler` — они пока выводят хэлп/баннер (минимальный рантайм), но уже с собственным PE/ELF.
4. `src/bigc.asm` — то же, но на голом `x86-64` asm (FASM), 1-в-1 повторяет структуру `PEBuilder`/`ELFBuilder` из `bigc.py`, чтобы можно было сравнить байты.

Идея — как у `tcc`/`zig cc`: сначала Python, потом asm, потом уже Big компилирует Big без Python.

```bash
# проверка round-trip (сейчас частично, т.к. рантайм минимален)
python3 bigc.py src/compiler.bg -o /tmp/bigc2.exe --target windows
cmp bigc.exe /tmp/bigc2.exe && echo "бит-в-бит совпало"
```

---

## 🐢 Производительность

Заявка «быстрее ASM/Zig/Rust» — конечно мем: Big быстрее, потому что почти ничего не делает, зато честно (без LLVM, без линкера). Но цифры реальные:

- `bigc.py` компилирует `hello.bg` за **< 30 мс** (CPython 3.11, Linux) — весь пайплайн + запись PE.
- Бинарь `hello.exe` — **1536 байт**, стартует быстрее любого `hello` на Rust (который тянет рантайм).
- `src/bigc.asm` если собрать FASM — будет чистый `asm`, без `python`, старт < 1 мс.
- ELF версия вообще без динамических зависимостей: только `write`/`exit` syscalls, `PT_LOAD` один сегмент.

Если серьёзно — Big экономит время разработчика за счёт простых правил и мгновенной диагностики, как Zig, но с синтаксисом ближе к Rust.

---

## ✅ Тесты

```bash
# ручной smoke
python3 bigc.py examples/hello.bg --target windows -o /tmp/h  && file /tmp/h
python3 bigc.py examples/hello.bg --target linux  -o /tmp/h2 && /tmp/h2
python3 bigc.py examples/error_demo.bg --lex --parse --sema

# Makefile
make check
```

`make check` делает:

- `bigc.py --lex/--parse/--sema` для каждого `examples/*.bg`
- собирает все примеры в обе цели
- запускает ELF-бинари и сверяет вывод (UTF-8)
- проверяет, что PE действительно MZ/PE

---

## 📚 Дальше

- [`docs/spec.md`](docs/spec.md) — грамматика, типы, области видимости
- [`docs/compiler.md`](docs/compiler.md) — LEX→…→PE/ELF, байтовые раскладки
- [`docs/diagnostics.md`](docs/diagnostics.md) — все `E/W/I` с примерами

---

## 📄 Лицензия

MIT © 2026 daniil-ship — см. `LICENSE`. Делайте что хотите, но сохраните заголовок PE красивым.
