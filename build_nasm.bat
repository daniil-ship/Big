@echo off
setlocal EnableExtensions
cd /d "%~dp0"

where nasm >nul 2>nul
if errorlevel 1 (
    echo ERROR: NASM is not in PATH.
    echo Install NASM from https://www.nasm.us/ and reopen the terminal.
    exit /b 1
)

rem --- сборка компилятора: чистый NASM -> самодостаточный PE64 без линкера ---
nasm -f bin -w+all src\bigc.asm -o bigc.exe
if errorlevel 1 exit /b %errorlevel%

for %%I in (bigc.exe) do echo [OK] bigc.exe: %%~zI bytes, pure-NASM PE64 compiler

rem --- smoke-тест: компилируем примеры и запускаем результаты ---
for %%F in (hello vars main fib) do (
    bigc.exe examples\%%F.bg -o examples\%%F.exe
    if errorlevel 1 (
        echo ERROR: bigc.exe failed on examples\%%F.bg
        exit /b 1
    )
    examples\%%F.exe
    if errorlevel 1 (
        echo ERROR: examples\%%F.exe failed at runtime
        exit /b 1
    )
)

rem --- демонстрация диагностик (ожидается ненулевой код выхода) ---
bigc.exe examples\error_demo.bg
if "%errorlevel%"=="0" (
    echo ERROR: error_demo.bg should fail with diagnostics
    exit /b 1
)

echo [OK] NASM build and smoke-tests passed.
endlocal
