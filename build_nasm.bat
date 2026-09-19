@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo [NOTE] The primary Windows 11 x64 compiler tool is bigc.exe (or bigc.cmd / bigc.bat).
echo Running native Windows 11 build and test suite...
echo.

call "%~dp0build_windows.bat"
if errorlevel 1 exit /b %errorlevel%

where nasm >nul 2>nul
if not errorlevel 1 (
    echo.
    echo Assembling NASM bootstrap to bigc_nasm.exe...
    nasm -f bin -w+all src\bigc.asm -o bigc_nasm.exe
    if not errorlevel 1 echo [OK] bigc_nasm.exe assembled.
)

endlocal
