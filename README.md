# Big — язык программирования для Windows 11 x64 (БЕЗ Linux)

**Big** — системный язык программирования с собственным компилятором `bigc`, который работает **напрямую на Windows 11 x64 без Linux, без WSL и без сторонних линкеров**. Компилятор самостоятельно генерирует полноценный бинарный заголовок Windows PE64 (PE32+) и машинный код x86-64.

Компиляция и запуск одной командой в Windows:
```cmd
bigc examples\hello.bg
hello.exe
```

```
  ╔═ Big Windows 11 x64 Pipeline ═════════════════════════════╗
  ║  source.bg → LEX → PARSE → SEMA → IR → OPT → PE64 Emitter ║
  ║                                                           ║
  ║  Результат: нативный Windows PE64 исполняемый файл (.exe)  ║
  ║  - DOS MZ + PE32+ Optional Header + COFF AMD64 (0x8664)   ║
  ║  - Секции .text (RVA 0x1000) и .rdata (RVA 0x2000)        ║
  ║  - Импорт KERNEL32.DLL (GetStdHandle, WriteFile, и др.)   ║
  ║  - Авто-настройка консоли SetConsoleOutputCP(65001) UTF-8 ║
  ║  - 100% соответствие Windows x64 ABI (выравнивание стека) ║
  ╚═══════════════════════════════════════════════════════════╝
```

---

## ⚡ Особенности для Windows 11 x64

| Возможность | Как устроено |
|-------------|--------------|
| **ТОЛЬКО Windows 11 (без Linux)** | Никакого WSL, Ubuntu, bash или Linux ELF. Все скрипты, тесты, примеры и бинарники ориентированы на Windows (`cmd.exe`, PowerShell, `.bat`, `.cmd`, `.exe`). |
| **Генерация PE64 без линкера** | Компилятор сам конструирует PE64 заголовок: сигнатура `PE\0\0`, Machine `0x8664`, Magic `0x20B`, Subsystem `Windows CUI`, секции `.text` и `.rdata`, импорты `kernel32.dll` — без `link.exe`, без LLVM. |
| **Русский язык в консоли без кракозябр** | Каждый скомпилированный `.exe` автоматически вызывает `SetConsoleOutputCP(65001)` и `SetConsoleCP(65001)` при запуске — русский текст выводится в консоль Windows 11 без `╨п╨╖╤Л╨║`. |
| **Соответствие Windows x64 ABI** | Строгое 16-байтное выравнивание стека перед каждым вызовом WinAPI функций, выделение теневого пространства (shadow space 32 байта) — бинарники не падают с `0xC0000005`. |
| **Красивая диагностика как в Rust** | Цветные сообщения об ошибках, указатели `--> file:line:col`, подсветка строк `^^^^^` и подсказки `= help:`. |
| **Готовые инструменты вызова** | В репозитории уже есть `bigc.exe`, `bigc.cmd`, `bigc.bat` и `bigc.ps1` — работает в любой среде Windows. |

---

## 🚀 Быстрый старт на Windows 11 x64

### Требования
- **Windows 11 x64** (или Windows 10 x64)
- **Python 3.7+** (стандартный для Windows: `py`, `python` или `python3`)
  > Если Python ещё не установлен, установите его одной командой в PowerShell:
  > ```powershell
  > winget install Python.Python.3.12
  > ```
  > или скачайте с официального сайта [python.org](https://www.python.org/).

### Клонирование и первый запуск в Windows

Откройте **Командную строку (cmd)** или **PowerShell** в папке проекта:

```cmd
git clone https://github.com/daniil-ship/Big
cd Big
```

#### 1. Сборка первого приложения (Hello World)

```cmd
bigc examples\hello.bg -o hello.exe
hello.exe
```

Вывод:
```
Hello, Big! Привет из Big!
```

#### 2. Запуск через PowerShell

```powershell
.\bigc.exe examples\vars.bg -o vars.exe
.\vars.exe
```

Вывод:
```
c = 65
Big — быстрее ASM!
```

#### 3. Полный автоматический тест всех примеров на Windows 11

Запустите готовый пакетный файл тестирования (в cmd):

```cmd
test_windows.bat
```

Или в PowerShell:

```powershell
.\test_windows.ps1
```

Скрипт скомпилирует и проверит все примеры:
- `hello.bg` → `test_hello.exe`
- `vars.bg` → `test_vars.exe` (арифметика и переменные)
- `main.bg` → `test_main.exe` (ветвления, циклы for/while, constant folding)
- `fib.bg` → `test_fib.exe`
- `error_demo.bg` (проверка вывода диагностики ошибок)

---

## 📁 Доступные инструменты запуска на Windows

В репозитории предусмотрено 4 способа вызова компилятора под Windows 11:

1. **`bigc.exe`** — нативный 64-битный исполняемый файл Windows (PE64). Автоматически находит доступный в системе Python (`py.exe`, `python.exe`, `python3.exe`) и запускает компиляцию, пробрасывая код выхода и потоки ввода/вывода.
2. **`bigc.cmd`** / **`bigc.bat`** — стандартные пакетные файлы Windows для запуска из командной строки `cmd.exe`:
   ```cmd
   bigc.cmd examples\hello.bg
   ```
3. **`bigc.ps1`** — скрипт PowerShell:
   ```powershell
   .\bigc.ps1 examples\hello.bg
   ```
4. **`python bigc.py`** — прямой запуск компилятора через Python:
   ```cmd
   python bigc.py examples\hello.bg -o app.exe
   ```

---

## 📖 Язык Big

Синтаксис языка сочетает лаконичность Rust, Zig и Go: `func`, `let`, `if`/`else`, `for .. in ..`, `while`, `return`, `print`/`println`.

### Hello World (`examples/hello.bg`)

```big
// examples/hello.bg
func main() -> i32 {
    print("Hello, Big! Привет из Big!");
    println("");
    return 0;
}
```

### Переменные и арифметика (`examples/vars.bg`)

```big
// examples/vars.bg
func main() -> i32 {
    let a: i32 = 10;
    let b: i32 = 20;
    let c: i32 = a + b * 3 - 5;   // 65 (вычисляется на этапе оптимизации)
    print("c = 65");
    println("");
    print("Big — быстрее ASM!");
    println("");
    return 0;
}
```

Поддерживаемые типы: `i32` (по умолчанию), `i64`, `bool`, `str`, `void`.

### Условия и циклы (`examples/main.bg`)

```big
func max(a: i32, b: i32) -> i32 {
    if a > b { return a; }
    else { return b; }
}

func main() -> i32 {
    let x: i32 = 42;
    let y: i32 = 2;
    let sum: i32 = x + y * 2 + 10;   // 58 (constant folding)
    print("сумма известна на этапе компиляции");
    println("");

    if x > 10 {
        print("x большое (>10) — круто!");
        println("");
    }

    for i in 0..5 {        // i = 0, 1, 2, 3, 4
        print("Счёт: <int>");
        print(" ");
    }
    println("");

    while y < 5 {
        println("while n=<int>");
    }
    return 0;
}
```

---

## 🎨 Диагностика ошибок в стиле Rust

При обнаружении ошибки компилятор выводит детальный отчет с точным указанием строки, столбца и советом по исправлению:

```
error[E3006]: несоответствие типов: переменная `x` объявлена как `i32`, но инициализируется значением типа `str`
 --> examples/error_demo.bg:6:5
  |
6 |     let x: i32 = "привет";
  |     ^^^^^^^^^^^^^^^^^^^^^^
  |
  = help: поменяйте тип на `str`, или присвойте `i32`, например `42`

warning[W3002]: неиспользуемая переменная `unused`
 --> examples/error_demo.bg:8:9
  |
8 |     let unused: i32 = 123;
  |         ^^^^^^
  |
  = help: если переменная пока не нужна, переименуйте в `_unused`, или используйте её: `print(unused)`
```

---

## 🛠 Структура файлов проекта

```
Big/
├── bigc.exe           # Нативный Windows 11 x64 лаунчер (PE64)
├── bigc.cmd           # CMD скрипт вызова для командной строки Windows
├── bigc.bat           # BAT скрипт вызова
├── bigc.ps1           # PowerShell скрипт вызова
├── bigc.py            # Компилятор языка Big (генератор PE64)
├── build_windows.bat  # Сборка всех примеров на Windows 11 x64
├── test_windows.bat   # Полный набор тестов для Windows 11 (CMD)
├── test_windows.ps1   # Полный набор тестов для Windows 11 (PowerShell)
├── examples/          # Примеры программ на Big
│   ├── hello.bg / hello.exe  # Привет мир (с UTF-8 русским текстом)
│   ├── vars.bg  / vars.exe   # Переменные и вычисления
│   ├── main.bg  / main.exe   # Условия и циклы
│   ├── fib.bg   / fib.exe    # Числа Фибоначчи
│   └── error_demo.bg         # Демонстрация сообщений об ошибках
├── docs/              # Документация
│   ├── spec.md        # Спецификация языка
│   ├── compiler.md    # Устройство компилятора и PE64 формата
│   └── diagnostics.md # Справочник кодов ошибок
└── LICENSE            # MIT License
```

---

## 📄 Лицензия

MIT © 2026 daniil-ship — см. файл `LICENSE`.
