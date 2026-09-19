$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$pyCmd = (Get-Command py, python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pyCmd) {
    Write-Error "[ERROR] Python 3 was not found in PATH. Please install Python 3: winget install Python.Python.3.12"
    exit 1
}
if ($pyCmd -like "*py.exe*") {
    & $pyCmd -3 "$scriptDir\bigc.py" @args
} else {
    & $pyCmd "$scriptDir\bigc.py" @args
}
exit $LASTEXITCODE
