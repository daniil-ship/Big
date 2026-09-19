@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================================
echo   Big Language - Native Windows 11 x64 Build & Test
echo ========================================================
echo.

where py >nul 2>nul
if %ERRORLEVEL% equ 0 (
    set "PY_CMD=py -3"
    goto found_py
)
where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    set "PY_CMD=python"
    goto found_py
)
where python3 >nul 2>nul
if %ERRORLEVEL% equ 0 (
    set "PY_CMD=python3"
    goto found_py
)

echo [ERROR] Python 3 was not found on your Windows 11 system.
echo Python is required to run the Big compiler.
echo Install Python via: winget install Python.Python.3.12
exit /b 1

:found_py
echo [1/3] Using Python: %PY_CMD%
%PY_CMD% --version
echo.

echo [2/3] Compiling all examples to Windows PE64 (.exe)...
%PY_CMD% "%~dp0bigc.py" examples\hello.bg -o examples\hello.exe
if errorlevel 1 goto error
%PY_CMD% "%~dp0bigc.py" examples\vars.bg -o examples\vars.exe
if errorlevel 1 goto error
%PY_CMD% "%~dp0bigc.py" examples\main.bg -o examples\main.exe
if errorlevel 1 goto error
%PY_CMD% "%~dp0bigc.py" examples\fib.bg -o examples\fib.exe
if errorlevel 1 goto error
echo   All examples built successfully.
echo.

echo [3/3] Running Windows 11 x64 smoke tests...
call "%~dp0test_windows.bat"
if errorlevel 1 goto error

echo.
echo ========================================================
echo   [OK] Big is ready and fully operational on Windows 11!
echo ========================================================
exit /b 0

:error
echo [FAILED] Build or test failed!
exit /b 1
