@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
where py >nul 2>nul
if %ERRORLEVEL% equ 0 (
    py -3 "%SCRIPT_DIR%bigc.py" %*
    exit /b %ERRORLEVEL%
)
where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python "%SCRIPT_DIR%bigc.py" %*
    exit /b %ERRORLEVEL%
)
where python3 >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python3 "%SCRIPT_DIR%bigc.py" %*
    exit /b %ERRORLEVEL%
)
echo [ERROR] Python 3 was not found in PATH.
echo The Big compiler requires Python 3.7+ to run on Windows 11.
echo Install Python: winget install Python.Python.3.12
exit /b 1
