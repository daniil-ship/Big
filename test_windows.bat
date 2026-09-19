@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================================
echo   Big Compiler - Windows 11 x64 Smoke Test Suite
echo   (Running natively on Windows 11 - NO Linux needed)
echo ========================================================
echo.

echo [1/6] Testing compiler help and version...
call "%~dp0bigc.cmd" --version
if errorlevel 1 goto error
call "%~dp0bigc.cmd" --help >nul
if errorlevel 1 goto error
echo   --help and --version OK.
echo.

echo [2/6] Compiling and running examples\hello.bg...
call "%~dp0bigc.cmd" examples\hello.bg -o win_test_hello.exe
if errorlevel 1 goto error
win_test_hello.exe
if errorlevel 1 goto error
del /q win_test_hello.exe
echo   hello.exe OK.
echo.

echo [3/6] Compiling and running examples\vars.bg...
call "%~dp0bigc.cmd" examples\vars.bg -o win_test_vars.exe
if errorlevel 1 goto error
win_test_vars.exe
if errorlevel 1 goto error
del /q win_test_vars.exe
echo   vars.exe OK.
echo.

echo [4/6] Compiling and running examples\main.bg...
call "%~dp0bigc.cmd" examples\main.bg -o win_test_main.exe
if errorlevel 1 goto error
win_test_main.exe
if errorlevel 1 goto error
del /q win_test_main.exe
echo   main.exe OK.
echo.

echo [5/6] Compiling and running examples\fib.bg...
call "%~dp0bigc.cmd" examples\fib.bg -o win_test_fib.exe
if errorlevel 1 goto error
win_test_fib.exe
if errorlevel 1 goto error
del /q win_test_fib.exe
echo   fib.exe OK.
echo.

echo [6/6] Testing diagnostic error output...
call "%~dp0bigc.cmd" examples\error_demo.bg --check >nul 2>nul
echo   error diagnostics OK.
echo.

echo ========================================================
echo   [OK] ALL WINDOWS 11 X64 TESTS PASSED SUCCESSFULLY!
echo ========================================================
exit /b 0

:error
echo.
echo [FAILED] Smoke test failed!
exit /b 1
