"""Fail closed when Android shared libraries are not 16 KB compatible."""
import argparse
import struct
from pathlib import Path
from zipfile import BadZipFile, ZipFile

PAGE_SIZE = 16384


def verify(data, expected_machine=None):
    if data[:4] != b'\x7fELF' or len(data) < 52:
        raise ValueError('Not an ELF file')
    if data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError('Unsupported ELF class or byte order')
    endian = '<' if data[5] == 1 else '>'
    is64 = data[4] == 2
    header = struct.unpack_from(endian + ('HHIQQQIHHHHHH' if is64 else 'HHIIIIIHHHHHH'), data, 16)
    if header[0] != 3 or header[1] not in (40, 62, 183):
        raise ValueError('Expected an Android ARM, ARM64 or x86_64 shared library')
    if expected_machine is not None and header[1] != expected_machine:
        raise ValueError('ELF architecture does not match its packaged ABI')
    fmt = endian + ('IIQQQQQQ' if is64 else 'IIIIIIII')
    if header[8] < struct.calcsize(fmt) or header[9] == 0:
        raise ValueError('Invalid program header table')
    loads = 0
    for index in range(header[9]):
        ph = struct.unpack_from(fmt, data, header[4] + index * header[8])
        offset, address, size, memory, alignment = ((ph[2], ph[3], ph[5], ph[6], ph[7]) if is64 else (ph[1], ph[2], ph[4], ph[5], ph[7]))
        if ph[0] == 1:
            loads += 1
            if alignment < PAGE_SIZE or alignment & (alignment - 1):
                raise ValueError(f'LOAD {index}: invalid alignment {alignment:#x}')
            if (address - offset) % PAGE_SIZE:
                raise ValueError(f'LOAD {index}: offset and address are not congruent')
            if size > memory or offset + size > len(data):
                raise ValueError(f'LOAD {index}: invalid segment extent')
        if ph[0] == 0x6474e552 and (address + memory) % PAGE_SIZE:
            raise ValueError(f'GNU_RELRO {index}: end is not 16 KB aligned')
    if not loads:
        raise ValueError('No LOAD segments')
    return loads


def verify_package(path):
    prefix = 'base/lib' if path.suffix == '.aab' else 'lib'
    with ZipFile(path) as package:
        for abi, machine in [('armeabi-v7a', 40), ('arm64-v8a', 183), ('x86_64', 62)]:
            member = f'{prefix}/{abi}/libjust_image_native.so'
            verify(package.read(member), expected_machine=machine)
            print(f'PASS {path.name}/{member}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('libraries', nargs='+', type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.libraries:
        try:
            if path.suffix in ('.apk', '.aab'):
                verify_package(path)
                continue
            loads = verify(path.read_bytes())
            print(f'PASS {path}: {loads} LOAD segments; GNU_RELRO end aligned when present')
        except (OSError, ValueError, struct.error, KeyError, BadZipFile) as error:
            print(f'FAIL {path}: {error}')
            failed = True
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
