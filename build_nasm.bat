@echo off
setlocal EnableExtensions
cd /d "%~dp0"

where nasm >nul 2>nul
if errorlevel 1 (
    echo ERROR: NASM is not in PATH.
    echo Install NASM from https://www.nasm.us/ and reopen the terminal.
    exit /b 1
)

nasm -f bin -w+all src\bigc.asm -o bigc.exe
if errorlevel 1 exit /b %errorlevel%

for %%I in (bigc.exe) do echo [OK] bigc.exe: %%~zI bytes, NASM flat PE64
if not exist bigc.exe (
    echo ERROR: NASM did not produce bigc.exe
    exit /b 1
)

rem Smoke-test the exact path that previously failed.
if exist temp.exe del /q temp.exe
bigc.exe examples\main.bg -o temp.exe
if errorlevel 1 exit /b %errorlevel%
if not exist temp.exe (
    echo ERROR: compiler did not create temp.exe
    exit /b 1
)

for %%I in (temp.exe) do (
    echo [OK] temp.exe: %%~zI bytes
    if not "%%~zI"=="3584" echo WARNING: expected a 3584-byte PE template
)

echo [OK] NASM build and temp.exe smoke-test passed.
endlocal
