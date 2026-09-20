#!/usr/bin/env python3
"""Строгий валидатор PE64 — повторяет проверки загрузчика Windows,
из-за которых появляется «Невозможно запустить это приложение»
(ERROR_BAD_EXE_FORMAT / STATUS_INVALID_IMAGE_FORMAT).

Без внешних зависимостей (только стандартная библиотека), работает и на
самой Windows 11. Использование:

    python tools\\validate_pe.py bigc.exe examples\\hello.exe ...

Код 0 = все файлы прошли проверку.
"""
import struct
import sys

SCN_MEM_EXECUTE = 0x20000000


def _u16(b, off):
    return struct.unpack_from('<H', b, off)[0]


def _u32(b, off):
    return struct.unpack_from('<I', b, off)[0]


def _u64(b, off):
    return struct.unpack_from('<Q', b, off)[0]


def _pow2(x):
    return x > 0 and (x & (x - 1)) == 0


def check(path):
    raw = open(path, 'rb').read()
    flen = len(raw)
    errs = []

    def req(cond, msg):
        if not cond:
            errs.append(msg)

    # --- DOS header ---
    req(flen >= 0x40, 'файл короче DOS-заголовка')
    req(_u16(raw, 0) == 0x5A4D, 'нет сигнатуры MZ')
    lfanew = _u32(raw, 0x3C)
    req(0x40 <= lfanew + 24 <= flen, 'e_lfanew указывает за пределы файла')
    if errs:
        return errs

    # --- COFF header ---
    req(_u32(raw, lfanew) == 0x00004550, 'нет сигнатуры PE')
    machine = _u16(raw, lfanew + 4)
    nsec = _u16(raw, lfanew + 6)
    size_opt = _u16(raw, lfanew + 20)
    req(machine == 0x8664, f'Machine={machine:#06x}, нужен x86-64 (0x8664)')
    req(size_opt >= 240, f'SizeOfOptionalHeader={size_opt}, нужно >= 240 для PE32+')
    req(1 <= nsec <= 96, f'NumberOfSections={nsec}')

    # --- Optional header (PE32+) ---
    opt = lfanew + 24
    req(opt + size_opt <= flen, 'optional header не помещается в файл')
    req(_u16(raw, opt) == 0x20B, 'магия optional header не 0x20B (PE32+)')
    entry = _u32(raw, opt + 16)
    image_base = _u64(raw, opt + 24)
    sec_align = _u32(raw, opt + 32)
    file_align = _u32(raw, opt + 36)
    size_of_image = _u32(raw, opt + 56)
    size_of_headers = _u32(raw, opt + 60)
    subsystem = _u16(raw, opt + 68)
    num_dirs = _u32(raw, opt + 108)

    req(_pow2(file_align), f'FileAlignment {file_align:#x} не степень двойки')
    req(_pow2(sec_align), f'SectionAlignment {sec_align:#x} не степень двойки')
    req(file_align <= sec_align, 'FileAlignment > SectionAlignment')
    req(size_of_headers % file_align == 0,
        f'SizeOfHeaders {size_of_headers:#x} не кратен FileAlignment')
    req(size_of_headers <= flen, 'SizeOfHeaders больше размера файла')
    hdr_end = opt + size_opt + 40 * nsec
    req(size_of_headers >= hdr_end,
        f'SizeOfHeaders {size_of_headers:#x} меньше конца заголовков секций ({hdr_end:#x})')
    req(size_of_image % sec_align == 0,
        f'SizeOfImage {size_of_image:#x} не кратен SectionAlignment')
    req(image_base % 0x10000 == 0, 'ImageBase не выровнен по 64K')
    req(subsystem == 3, f'Subsystem={subsystem}, нужна консоль (3)')
    req(num_dirs >= 13, f'NumberOfRvaAndSizes={num_dirs}, нужно >= 13 (есть IAT)')

    # --- Section headers ---
    dirs_off = opt + 112
    secs = []
    va_end = sec_align  # первая секция должна начинаться не раньше Alignment
    for i in range(nsec):
        sh = opt + size_opt + 40 * i
        name = raw[sh:sh + 8].rstrip(b'\0').decode('ascii', 'replace')
        vsize = _u32(raw, sh + 8)
        va = _u32(raw, sh + 12)
        rawsize = _u32(raw, sh + 16)
        rawptr = _u32(raw, sh + 20)
        chars = _u32(raw, sh + 36)
        secs.append((name, va, vsize, rawptr, rawsize, chars))
        req(rawptr % file_align == 0,
            f'{name}: PointerToRawData {rawptr:#x} не кратен FileAlignment')
        req(rawsize % file_align == 0,
            f'{name}: SizeOfRawData {rawsize:#x} не кратен FileAlignment')
        req(va % sec_align == 0,
            f'{name}: VirtualAddress {va:#x} не кратен SectionAlignment')
        req(rawptr >= size_of_headers,
            f'{name}: данные секции перекрывают заголовки')
        req(rawptr + rawsize <= flen,
            f'{name}: PointerToRawData+SizeOfRawData = {rawptr + rawsize:#x} '
            f'выходит за конец файла ({flen:#x})')
        req(va >= va_end,
            f'{name}: виртуальные адреса секций не по возрастанию')
        va_end = va + max(vsize, sec_align)
        req(vsize == 0 or vsize <= rawsize,
            f'{name}: VirtualSize {vsize:#x} > SizeOfRawData {rawsize:#x}')

    req(va_end <= size_of_image,
        f'секции ({va_end:#x}) выходят за SizeOfImage ({size_of_image:#x})')

    # --- Entry point: внутри исполняемой секции ---
    entry_sec = None
    for s in secs:
        name, va, vsize, _, _, chars = s
        if va <= entry < va + max(vsize, 1):
            entry_sec = s
    req(entry_sec is not None,
        f'AddressOfEntryPoint {entry:#x} не внутри ни одной секции')
    if entry_sec:
        req(entry_sec[5] & SCN_MEM_EXECUTE,
            f'секция {entry_sec[0]} с точкой входа не имеет флага MEM_EXECUTE')

    # --- Каталоги данных внутри секций ---
    def inside(va, size, what):
        if not size:
            return
        ok = any(sva <= va and va + size <= sva + max(sv, 1)
                 for _, sva, sv, _, _, _ in secs)
        req(ok, f'{what} {va:#x}+{size:#x} вне секций')

    if num_dirs >= 2:
        inside(_u32(raw, dirs_off + 8), _u32(raw, dirs_off + 12), 'каталог импорта')
    if num_dirs >= 13:
        inside(_u32(raw, dirs_off + 96), _u32(raw, dirs_off + 100), 'IAT')

    return errs


def main():
    if len(sys.argv) < 2:
        print('использование: python tools/validate_pe.py <файл.exe> [...]')
        return 2
    ok = True
    for path in sys.argv[1:]:
        try:
            errs = check(path)
        except OSError as e:
            print(f'{path}: НЕ ПРОЧИТАТЬ ({e})')
            ok = False
            continue
        if errs:
            print(f'{path}: НЕВЕРНЫЙ ФОРМАТ')
            for e in errs:
                print('   -', e)
            ok = False
        else:
            print(f'{path}: OK')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
