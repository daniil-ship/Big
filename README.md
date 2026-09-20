# Big — язык со своим компилятором на чистом NASM (Windows 11 x64)

**Big** — маленький системный язык с компилятором `bigc`, который **сам делает
заголовок PE64 без линкера**. Компилятор написан **целиком на NASM**
(один файл `src/bigc.asm`, ни строчки C или Python), цель — **только
Windows 11 x64**: `.bg` → самодостаточный `.exe` одной командой.

```
bigc.exe main.bg  →  main.exe   (PE64, ImageBase 0x140000000)
```

```
  ╔═ Big Pipeline ═══════════════════════════════════════╗
  ║  source.bg → LEX → PARSE → SEMA → CODEGEN → BUILD_PE ║
  ║                       ↓                              ║
  ║             PE64 (.text + .rdata, импорт kernel32)   ║
  ╚══════════════════════════════════════════════════════╝
  ELF/Linux не поддерживается — только Windows.
```

## Возможности языка

- функции с параметрами и **настоящая рекурсия** (`fib.bg`);
- `let` с типами `i32` / `str`, присваивание `n = n - 1`;
- `if/else`, `while`, `for i in a..b` (конец не включается);
- `print` / `println` для строк (UTF-8 как есть) и целых;
- приоритеты операций, скобки, унарные `-` и `!`;
- константное свёртывание; диагностики в стиле `error: ...` с кодом выхода 1.

Подробности: [docs/spec.md](docs/spec.md), [docs/compiler.md](docs/compiler.md),
[docs/diagnostics.md](docs/diagnostics.md).

## Быстрый старт (Windows 11 x64)

Единственное требование — **NASM 2.15+** в `PATH` ([nasm.us](https://www.nasm.us/)).

```bat
:: собрать компилятор (один вызов nasm, без линкера)
nasm -f bin src\bigc.asm -o bigc.exe

:: или готовый скрипт: сборка + прогон всех примеров
build_nasm.bat

:: скомпилировать и запустить программу
bigc.exe examples\fib.bg -o fib.exe
fib.exe
:: fib(10) = 55
```

В репозитории уже лежит собранный `bigc.exe` — можно сразу компилировать.

`make` (nmake/mingw32-make) тоже работает: `nmake /F Makefile` соберёт
компилятор и все примеры.

## Пример

```big
// examples/vars.bg
func main() -> i32 {
    let a: i32 = 10;
    let b: i32 = 20;
    let c: i32 = a + b * 3 - 5;
    print("c = ");
    print(c);
    println("");

    let s: str = "Big — быстрее ASM!";
    print(s);
    println("");
    return 0;
}
```

```
$ bigc.exe examples\vars.bg -o vars.exe && vars.exe
c = 65
Big — быстрее ASM!
```

## Примеры

| Файл | Что показывает |
|------|----------------|
| `examples/hello.bg` | минимальная программа, UTF-8 строка |
| `examples/vars.bg` | переменные `i32`/`str`, арифметика с приоритетами |
| `examples/main.bg` | `if/else`, `for`, `while`, присваивание |
| `examples/fib.bg` | функции с параметрами, рекурсия |
| `examples/error_demo.bg` | диагностики: неверный тип, неизвестная переменная |

Скомпилированные `examples/*.exe` лежат рядом и запускаются напрямую
в любой консоли Windows 11 x64.

## Как устроен компилятор

- **Один файл** `src/bigc.asm` (~5000 строк, чистый NASM, `-f bin`).
  Файл сам содержит свой PE-заголовок и импорты `kernel32.dll`
  (`GetCommandLineA`, `CreateFileA`, `ReadFile`, `WriteFile`,
  `GetStdHandle`, `ExitProcess`, `VirtualAlloc`, …), поэтому NASM сразу
  выдаёт готовый `.exe` — линкер не нужен.
- Память — арены на `VirtualAlloc` (токены, узлы AST, код, rdata, выход).
- Выходная программа получает собственный рантайм: `print_str`, `print_int`,
  `newline`, точку входа с `SetConsoleOutputCP(65001)` и `ExitProcess`.
- Подробнее — в [docs/compiler.md](docs/compiler.md).

## Структура репозитория

```
src/bigc.asm        — компилятор (чистый NASM, единственный исходник)
bigc.exe            — собранный компилятор (готов к запуску)
examples/*.bg       — примеры на Big
examples/*.exe      — примеры, скомпилированные этим компилятором
build_nasm.bat      — сборка + smoke-тесты одной командой (Windows)
Makefile            — цели compiler/examples/demo-errors/clean
docs/               — спецификация языка, устройство компилятора, диагностики
```
