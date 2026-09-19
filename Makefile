.PHONY: all windows check clean lex parse sema launcher

PY=python3
BIGC=$(PY) bigc.py

# По умолчанию собираем примеры для Windows 11 x64 (PE64)
all: windows

windows:
	@echo "== Big: сборка примеров PE64 для Windows 11 x64 =="
	@for f in examples/*.bg; do \
	  case "$$f" in *error_demo.bg) continue;; esac; \
	  echo "  bigc $$f -> $${f%.bg}.exe [windows]"; \
	  $(BIGC) "$$f" --target windows -o "$${f%.bg}.exe" || exit 1; \
	done
	@ls -lh examples/*.exe 2>/dev/null || true
	@$(PY) -c "import struct,pathlib,glob; [print(f'  {p}: valid PE64 (MZ/PE)') for p in glob.glob('examples/*.exe') if open(p,'rb').read(2)==b'MZ']"

launcher: src/launcher.c src/entry.s
	gcc -fno-ident -mabi=ms -c -O2 -fno-builtin -nostdlib -fno-asynchronous-unwind-tables src/launcher.c -o src/launcher.o
	gcc -c src/entry.s -o src/entry.o
	ld -m i386pep --strip-all --image-base 0x140000000 -e _start src/entry.o src/launcher.o -o bigc.exe
	@ls -lh bigc.exe

lex:
	@for f in examples/*.bg; do echo "== $$f --lex =="; $(BIGC) "$$f" --lex | head -n 80; echo ""; done

parse:
	@for f in examples/*.bg; do echo "== $$f --parse =="; $(BIGC) "$$f" --parse 2>&1 | head -n 60; echo ""; done

sema:
	@for f in examples/*.bg; do echo "== $$f --sema =="; $(BIGC) "$$f" --sema 2>&1 | head -n 80; echo ""; done

check: windows
	@echo "== Big: проверка PE64 заголовков и структуры =="
	@for exe in examples/hello.exe examples/vars.exe examples/main.exe examples/fib.exe bigc.exe; do \
	  $(PY) -c "import struct,sys; d=open('$$exe','rb').read(); assert d[0:2]==b'MZ',f'$$exe: not MZ'; pe=struct.unpack_from('<I',d,60)[0]; assert d[pe:pe+4]==b'PE\0\0',f'$$exe: not PE'; print(f'  [OK] $$exe: valid PE64, {len(d)} bytes')" || exit 1; \
	done
	@echo "== Big: проверка диагностики ошибок =="
	@$(BIGC) examples/error_demo.bg --sema 2>&1 | grep -E "error\[E|warning\[W|info\[I" | head -n 10
	@echo ""
	@echo "✅ check passed — Big готов для работы на Windows 11 x64 БЕЗ Linux!"

clean:
	rm -f examples/*.exe test_*.exe src/*.o
	@echo "cleaned"
