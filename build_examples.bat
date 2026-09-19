@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================================
echo   Big Compiler - Windows 11 x64 Examples Build
echo ========================================================
echo.

call "%~dp0bigc.cmd" examples\hello.bg -o examples\hello.exe
if errorlevel 1 goto error

call "%~dp0bigc.cmd" examples\vars.bg -o examples\vars.exe
if errorlevel 1 goto error

call "%~dp0bigc.cmd" examples\main.bg -o examples\main.exe
if errorlevel 1 goto error

call "%~dp0bigc.cmd" examples\fib.bg -o examples\fib.exe
if errorlevel 1 goto error

echo.
echo [OK] All examples successfully built for Windows 11 x64!
exit /b 0

:error
echo.
echo [ERROR] Build failed!
exit /b 1
