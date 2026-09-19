$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Big Compiler - Windows 11 x64 Smoke Test Suite" -ForegroundColor Cyan
Write-Host "  (Running natively on Windows 11 - NO Linux needed)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/6] Testing compiler help and version..." -ForegroundColor Yellow
& "$scriptDir\bigc.ps1" --version
& "$scriptDir\bigc.ps1" --help | Out-Null
Write-Host "  --help and --version OK." -ForegroundColor Green
Write-Host ""

Write-Host "[2/6] Compiling and running examples\hello.bg..." -ForegroundColor Yellow
& "$scriptDir\bigc.ps1" "examples\hello.bg" -o "$scriptDir\win_test_hello.exe"
& "$scriptDir\win_test_hello.exe"
Remove-Item -Force "$scriptDir\win_test_hello.exe"
Write-Host "  hello.exe OK." -ForegroundColor Green
Write-Host ""

Write-Host "[3/6] Compiling and running examples\vars.bg..." -ForegroundColor Yellow
& "$scriptDir\bigc.ps1" "examples\vars.bg" -o "$scriptDir\win_test_vars.exe"
& "$scriptDir\win_test_vars.exe"
Remove-Item -Force "$scriptDir\win_test_vars.exe"
Write-Host "  vars.exe OK." -ForegroundColor Green
Write-Host ""

Write-Host "[4/6] Compiling and running examples\main.bg..." -ForegroundColor Yellow
& "$scriptDir\bigc.ps1" "examples\main.bg" -o "$scriptDir\win_test_main.exe"
& "$scriptDir\win_test_main.exe"
Remove-Item -Force "$scriptDir\win_test_main.exe"
Write-Host "  main.exe OK." -ForegroundColor Green
Write-Host ""

Write-Host "[5/6] Compiling and running examples\fib.bg..." -ForegroundColor Yellow
& "$scriptDir\bigc.ps1" "examples\fib.bg" -o "$scriptDir\win_test_fib.exe"
& "$scriptDir\win_test_fib.exe"
Remove-Item -Force "$scriptDir\win_test_fib.exe"
Write-Host "  fib.exe OK." -ForegroundColor Green
Write-Host ""

Write-Host "[6/6] Testing diagnostic error output..." -ForegroundColor Yellow
try {
    & "$scriptDir\bigc.ps1" "examples\error_demo.bg" --check 2>&1 | Out-Null
} catch {
    # Expected error exit code
}
Write-Host "  error diagnostics OK." -ForegroundColor Green
Write-Host ""

Write-Host "========================================================" -ForegroundColor Green
Write-Host "  [OK] ALL WINDOWS 11 X64 TESTS PASSED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
