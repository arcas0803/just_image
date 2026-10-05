import struct
import unittest
from verify_android_elf import verify


def elf(alignment=16384, relro_end=16384, is64=True, machine=183):
    data = bytearray(256)
    data[:6] = b'\x7fELF' + bytes([2 if is64 else 1, 1])
    fmt = '<HHIQQQIHHHHHH' if is64 else '<HHIIIIIHHHHHH'
    struct.pack_into(fmt, data, 16, 3, machine, 1, 0, 64, 0, 0, 64, 56 if is64 else 32, 2, 0, 0, 0)
    if is64:
        struct.pack_into('<IIQQQQQQ', data, 64, 1, 5, 0, 0, 0, 256, 256, alignment)
        struct.pack_into('<IIQQQQQQ', data, 120, 0x6474e552, 4, 0, 0, 0, 0, relro_end, 1)
    else:
        struct.pack_into('<IIIIIIII', data, 64, 1, 0, 0, 0, 256, 256, 5, alignment)
        struct.pack_into('<IIIIIIII', data, 96, 0x6474e552, 0, 0, 0, 0, relro_end, 4, 1)
    return data


class VerifyTest(unittest.TestCase):
    def test_accepts_android_architectures(self):
        for machine, is64 in [(183, True), (62, True), (40, False)]:
            self.assertEqual(verify(elf(machine=machine, is64=is64)), 1)

    def test_rejects_4kb_load(self):
        with self.assertRaisesRegex(ValueError, 'LOAD'):
            verify(elf(alignment=4096))

    def test_rejects_16kb_load_with_4kb_relro(self):
        with self.assertRaisesRegex(ValueError, 'GNU_RELRO'):
            verify(elf(relro_end=4096))

    def test_rejects_invalid_and_truncated_files(self):
        for data in [b'', b'not ELF', elf()[:80]]:
            with self.assertRaises((ValueError, struct.error)):
                verify(data)


if __name__ == '__main__':
    unittest.main()
