# Big — сборка компилятора и примеров (только Windows 11 x64, PE64)
#
# Требования: NASM 2.15+ в PATH.
# На Windows:  nmake /F Makefile   (или mingw32-make)
# Все цели создают только Windows-бинарники (.exe). Никакого Linux/ELF.

NASM   ?= nasm
SRC    = src\bigc.asm
BIGC   = bigc.exe
EXAMPLES = examples\hello.bg examples\vars.bg examples\main.bg examples\fib.bg

all: compiler examples

# Собрать сам компилятор: один файл на чистом NASM -> самодостаточный PE64,
# без линкера, без C, без Python.
compiler: $(SRC)
	$(NASM) -f bin -w+all $(SRC) -o $(BIGC)

# Скомпилировать все примеры новым компилятором: .bg -> .exe (PE64)
examples: $(BIGC)
	$(BIGC) examples\hello.bg -o examples\hello.exe
	$(BIGC) examples\vars.bg  -o examples\vars.exe
	$(BIGC) examples\main.bg  -o examples\main.exe
	$(BIGC) examples\fib.bg   -o examples\fib.exe
	@echo [OK] examples built

# Демонстрация диагностик (ошибки типов и неизвестной переменной)
demo-errors: $(BIGC)
	$(BIGC) examples\error_demo.bg

clean:
	-del /q examples\hello.exe examples\vars.exe examples\main.exe examples\fib.exe 2>nul
	@echo cleaned

.PHONY: all compiler examples demo-errors clean
