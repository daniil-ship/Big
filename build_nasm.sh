#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"

make launcher
printf '[OK] bigc.exe ready for Windows 11 x64\n'
