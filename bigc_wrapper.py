#!/usr/bin/env python3
import sys
from pathlib import Path
import runpy
# Wrapper for Linux: delegates to bigc.py (the real compiler)
# This file is installed as ./bigc
sys.argv[0]=str(Path(__file__).parent/"bigc.py")
runpy.run_path(str(Path(__file__).parent/"bigc.py"), run_name="__main__")

