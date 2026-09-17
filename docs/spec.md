# Спецификация языка Big v0.1.0

> Этот документ описывает то, что **реально** реализовано в `bigc.py` (и повторено в `src/bigc.asm`). Не планы — факт.

## 1. Лексика

### 1.1 Кодировка
Исходник — UTF-8. Строковые литералы — UTF-8, в PE/ELF пишутся как есть (без BOM, без перекодировки). Компилятор сохраняет байты литерала дословно.

### 1.2 Токены

```
IDENT       [A-Za-z_][A-Za-z0-9_]*
INT         [0-9]+            (десятичные, без суффиксов, парсятся в i32/i64)
STRING      " ... "           с экранированием \" \\ \n \t \0 \r
COMMENT     // ... до конца строки
            /* ... */  блочный, может быть вложенным? — нет, но E1002 если не закрыт
KEYWORDS    func fn let var const if else while for in return use import true false break continue
OPS         + - * / % == != < > <= >= && || ! = -> : :: . .. , ; ( ) { } [ ] 
            // .. — диапазон в for, -> — возврат, :: — пока не используется
EOF
```

Whitespace и комментарии игнорируются, но `//` и `/*` отслеживаются в `line/col`.

Экранирование в строках:
- `\"` → `"`
- `\\` → `\`
- `\n` → LF
- `\t` → TAB
- `\0` → NUL
- `\r` → CR
- иное `\x` → `W1003` unknown escape, сохраняется как есть.

Незакрытая строка — `E1001`. Незакрытый `/*` — `E1002`. Неизвестный символ вне ASCII — `E1000`.

### 1.3 Ключевые слова vs идентификаторы
Все keywords резервированы. `print`/`println` — не keywords, а обычные идентификаторы, но в `SEMA` и `CG` трактуются как встроенные (intrinsic) — проверка `callee == "print"` ведёт к эмиту `WriteFile`/`write`.

## 2. Грамматика

EBNF, как в `parser_parse` (рекурсивный спуск + Pratt):

```
program      ::= ( useDecl | constDecl | funcDecl )* EOF
useDecl      ::= ("use"|"import") STRING ";"?
constDecl    ::= "const" IDENT (":" type)? "=" expr ";"?
funcDecl     ::= ("func"|"fn") IDENT "(" params? ")" ("->" type)? block
params       ::= param ("," param)*
param        ::= IDENT ":" type
type         ::= IDENT               // i32 | i64 | bool | str | void
block        ::= "{" stmt* "}"
stmt         ::= letStmt | constStmt | ifStmt | whileStmt | forStmt
              |  returnStmt | breakStmt | continueStmt
              |  assignStmt | exprStmt
letStmt      ::= ("let"|"var") IDENT (":" type)? ("=" expr)? ";"?
constStmt    ::= "const" IDENT (":" type)? "=" expr ";"?
ifStmt       ::= "if" expr block ("else" (ifStmt|block))?
whileStmt    ::= "while" expr block
forStmt      ::= "for" IDENT "in" expr ".." expr block
returnStmt   ::= "return" expr? ";"?
breakStmt    ::= "break" ";"?
continueStmt ::= "continue" ";"?
assignStmt   ::= IDENT "=" expr ";"?
exprStmt     ::= expr ";"?
expr         ::= unary ( (binOp) unary )*
binOp        ::= "||" | "&&" | "==" | "!=" | "<" | ">" | "<=" | ">="
              |  "+" | "-" | "*" | "/" | "%"
unary        ::= ("!"|"-")* primary
primary      ::= INT | STRING | "true" | "false"
              |  IDENT ("(" args? ")")?
              |  "(" expr ")"
              |  block                    // не используется как expr сейчас
args         ::= expr ("," expr)*
```

Приоритеты (Pratt, как в `parse_expr`):
```
1: || 
2: &&
3: == !=
4: < > <= >=
5: + -
6: * / %
7: унарные ! -
```

### 2.1 Точки с запятой
`;` — **рекомендуется**, но не обязательна в конце блока: если токен следующий `}` или `EOF`, `W2001/W2002` (warning, не error). Парсер восстанавливается и продолжает.

### 2.2 Блоки
`{ … }` обязательны для `if`/`while`/`for`/`func`. Отсутствие `{` — `E2004` + восстановление. Отсутствие `}` — `E2001` с указанием строки где блок начался.

## 3. Типы

```
i32   32-бит знаковое (по умолчанию для целых)
i64   64-бит знаковое
bool  true/false
str   UTF-8 строки, литералы "…"
void  отсутствие значения (функции без ->)
```

- Вывод типов: `let x = 42` → `i32` (E3005 `W3005` если не удалось вывести — fallback `i32` с warning).
- `let x: i32 = "hi"` → `E3006` (mismatch) + help.
- `i32` ↔ `i64` в бинарной операции → `W3010` mixed numeric, но компилируется (берётся левый).
- `!` на не-`bool` → `W3009` (обычно для `bool`).
- Сравнение `str` с `i32` → `E3015` operator can't apply.
- Функции: проверяется `E3013` (кол-во аргументов), `E3014` (типы аргументов), `E3009/E3010` (return type).

### 3.1 Области видимости
Стек `Scope(parent)`:
- `declare(name, type, span)` → `E3001` если уже есть в текущем scope, `I3002` если тень из родителя.
- `resolve(name)` ищет вверх.
- После анализа `check_unused` → `W3002` для каждой нечитанной `let` (кроме `_…`).

## 4. Выражения и семантика

- `a + b * 3 - 5` — обычный precedence, константы сворачиваются на этапе `OPT`/`CG`.
- `for i in 0..10` — `..` требует два выражения; `E2005` если нет `..`. Сейчас `CG` поддерживает только `0..N` где `N` — константа `i32`; тело эмитит `cmp`+`jl`+`jmp`.
- `if cond { … } else { … }` — `cond` должен быть `bool`; если `i32` — `W3006`, но эмитит `cmp rax,0 / je`.
- `while cond { … }` — аналогично.
- `return expr` — проверяется совместимость с `func` `-> type` (`E3009`/`W3007`/`E3010`).
- `print("…")` / `println("…")` — intrinsic. В `SEMA` `E9999` если >4 аргументов (ограничение рантайма). В `CG` — см. ниже.

## 5. Рантайм и кодоген

### 5.1 Windows (PE)
```
print(s):
  h = GetStdHandle(-11)          // STD_OUTPUT_HANDLE
  WriteFile(h, s.ptr, s.len, &written, 0)
  // строки лежат в .rdata, длина известна на этапе CG
```
Локальные `let` — `[rbp - N*8]`, `i32` хранится как `qword` (расширение). `call` функций — `E8 rel32` с фиксом `fixups`.

### 5.2 Linux (ELF)
```
print(s):
  mov rax,1; mov rdi,1; mov rsi,s.ptr; mov rdx,s.len; syscall // write
exit:
  mov rax,60; xor rdi,rdi; syscall
```

### 5.3 Constant folding
`eval_const_int(expr, var_init_map)` рекурсивно вычисляет `BinaryExpr`/`UnaryExpr`/`Var` если `var` инициализирован константой. Поэтому:
```big
let a: i32 = 10;
let b: i32 = 20;
let c: i32 = a + b * 3 - 5; // → 65, уже число в бинаре
```
— это `CG` подставит `mov rax,65` без рантайма. А `for i`/`while` переменные — не константы, поэтому `print(i)` сейчас → `<int>` (затычка `add_string("<int>")`).

## 6. Модули
`use` / `import "path"` — парсятся (`parse_use`), но `SEMA` пока игнорирует (задел на будущее). `const NAME = expr` — глобальные константы, поддерживаются в `Scope`.

## 7. Точка входа
- Ищется `func main` → `I3001` info.
- Нет `main` → `W3000`, но бинарь всё равно соберётся (entry — первая функция).
- Нет функций вообще → `E3005`.
- Дубли `func foo` → `E3000`.

## 8. Пример полной программы (валидной)

```big
use "std/io";

const GREETING: str = "Привет, Big!";

func max(a: i32, b: i32) -> i32 {
    if a > b {
        return a;
    } else {
        return b;
    }
}

func main() -> i32 {
    let x: i32 = 42;
    let y: i32 = 10;
    let m: i32 = max(x, y);
    if m > 20 {
        print(GREETING);
        println(" — максимум найден");
    }
    for i in 0..3 {
        print("i=<int> ");
    }
    println("");
    return 0;
}
```

## 9. Ограничения v0.1 и план

| Сейчас | План |
|--------|------|
| `print(i)` для не-констант → `<int>` | `itoa` рантайм |
| `for` только `0..N` const | произвольные выражения + `..=` |
| нет `else if` без блока? — есть (`else if`) | добавить `match` |
| массивов/структур нет | `[]T`, `struct`, `enum` |
| нет `import` резолва | файлы + `use` |
| 4 аргумента макс | стек `push` для остальных |
