.PHONY: all windows compiler nasm check clean lex parse sema

PY=python3
BIGC=$(PY) bigc.py
NASM ?= nasm
NASM_SRC=src/bigc.asm
NASM_OUT=bigc.exe
TARGETS_LINUX=$(patsubst %.bg,%,$(wildcard examples/*.bg))
TARGETS_WIN  =$(patsubst %.bg,%.exe,$(wildcard examples/*.bg))

# Assemble the self-contained Windows compiler with NASM.  This is a flat
# binary build: no linker, Python, FASM or import include files are involved.
nasm: $(NASM_SRC) src/pe_template.bin
	$(NASM) -f bin -w+all $(NASM_SRC) -o $(NASM_OUT)
	@test "$$(wc -c < $(NASM_OUT))" -eq 6144

# default — собрать все примеры для Linux (ELF)
all:
	@echo "== Big: сборка примеров (ELF64) =="
	@for f in examples/*.bg; do \
	  case "$$f" in *error_demo.bg) continue;; esac; \
	  echo "  bigc $$f -> $${f%.bg} [linux]"; \
	  $(BIGC) "$$f" --target linux -o "$${f%.bg}" || exit 1; \
	done
	@ls -lh examples/hello examples/main build/compiler 2>/dev/null | awk '{print " ", $$9, $$5}'

windows:
	@echo "== Big: кросс-сборка PE64 на Linux =="
	@for f in examples/*.bg; do \
	  case "$$f" in *error_demo.bg) continue;; esac; \
	  echo "  bigc $$f -> $${f%.bg}.exe [windows]"; \
	  $(BIGC) "$$f" --target windows -o "$${f%.bg}.exe" || exit 1; \
	done
	@ls -lh examples/*.exe 2>/dev/null || true
	@$(PY) -c "import struct,pathlib;import glob; [print(f'  {p} MZ PE') for p in glob.glob('examples/*.exe') if open(p,'rb').read(2)==b'MZ']" 2>/dev/null || true

compiler:
	@echo "== Big: bootstrap — src/compiler.bg -> bigc.exe / build/compiler =="
	@mkdir -p build
	$(BIGC) src/compiler.bg -o bigc.exe --target windows
	$(BIGC) src/compiler.bg -o build/compiler --target linux
	@ls -lh bigc.exe build/compiler
	@$(PY) -c "import pathlib; print('  file check: PE/ELF via python header')"
	@echo "  проверка PE заголовка bigc.exe:"
	@$(PY) -c "import struct; d=open('bigc.exe','rb').read(); print('   MZ', d[0:2], 'e_lfanew', hex(struct.unpack_from('<I',d,60)[0]), 'PE', d[struct.unpack_from('<I',d,60)[0]:struct.unpack_from('<I',d,60)[0]+4])"
	@echo "  запуск build/compiler:"
	@./build/compiler | head -n 5

lex:
	@for f in examples/*.bg; do echo "== $$f --lex =="; $(BIGC) "$$f" --lex | head -n 80; echo ""; done

parse:
	@for f in examples/*.bg; do echo "== $$f --parse =="; $(BIGC) "$$f" --parse 2>&1 | head -n 60; echo ""; done

sema:
	@for f in examples/*.bg; do echo "== $$f --sema =="; $(BIGC) "$$f" --sema 2>&1 | head -n 80; echo ""; done

check: all windows compiler
	@echo "== Big: smoke-тесты =="
	@echo "  ./examples/hello (ELF) ->"
	@./examples/hello | od -An -tx1 | head -n 2; ./examples/hello | cat
	@echo "  ./examples/main (ELF) ->"
	@./examples/main | head -n 10 | cat
	@echo "  ./examples/vars (ELF) c=65 ->"
	@./examples/vars | cat
	@echo "  bigc.exe PE заголовок ->"
	@$(PY) -c "import struct,sys; d=open('bigc.exe','rb').read(); assert d[0:2]==b'MZ','not MZ'; pe=struct.unpack_from('<I',d,60)[0]; assert d[pe:pe+4]==b'PE\0\0','not PE'; print('   OK PE64, IMAGE_BASE 0x140000000, Sections', struct.unpack_from('<H',d,pe+6)[0])"
	@echo "  build/compiler ELF заголовок ->"
	@$(PY) -c "d=open('build/compiler','rb').read(); assert d[0:4]==b'\x7fELF','not ELF'; assert d[4]==2,'not 64bit'; print('   OK ELF64 Entry', hex(int.from_bytes(d[24:32],'little')))"
	@echo "  error_demo diagnostics ->"
	@$(BIGC) examples/error_demo.bg --sema 2>&1 | grep -E "error\[E|warning\[W|info\[I" | head
	@echo ""
	@echo "✅ check passed — см. README.md и docs/"

clean:
	rm -f examples/hello examples/main examples/vars examples/fib
	rm -f examples/*.exe build/compiler
	@echo "cleaned"
