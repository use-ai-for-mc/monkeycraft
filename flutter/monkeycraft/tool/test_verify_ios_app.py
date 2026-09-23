import importlib.util
import struct
import sys
import unittest
from pathlib import Path

MODULE = Path(__file__).with_name("verify_ios_app.py")
SPEC = importlib.util.spec_from_file_location("verify_ios_app", MODULE)
assert SPEC is not None and SPEC.loader is not None
verify_ios_app = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = verify_ios_app
SPEC.loader.exec_module(verify_ios_app)


def thin(cputype: int, platform: int) -> bytes:
    command = struct.pack("<IIIIII", verify_ios_app.LC_BUILD_VERSION, 24, platform, 0, 0, 0)
    return struct.pack("<IiiIIIII", verify_ios_app.MH_MAGIC_64, cputype, 0, 6, 1, len(command), 0, 0) + command


def fat(slices: list[tuple[int, bytes]]) -> bytes:
    offset = 8 + len(slices) * 20
    entries = []
    payload = bytearray()
    for cputype, slice_ in slices:
        entries.append(struct.pack(">IIIII", cputype, 0, offset, len(slice_), 0))
        payload.extend(slice_)
        offset += len(slice_)
    return struct.pack(">II", verify_ios_app.FAT_MAGIC, len(slices)) + b"".join(entries) + payload


class ParseMachOTest(unittest.TestCase):
    def test_device_arm64_slice(self) -> None:
        slices = verify_ios_app.parse_macho_slices(thin(verify_ios_app.CPU_TYPE_ARM64, 2))
        self.assertEqual(slices, [verify_ios_app.MachOSlice(verify_ios_app.CPU_TYPE_ARM64, 2)])

    def test_simulator_fat_slice_is_visible(self) -> None:
        binary = fat([
            (verify_ios_app.CPU_TYPE_ARM64, thin(verify_ios_app.CPU_TYPE_ARM64, 7)),
            (0x01000007, thin(0x01000007, 7)),
        ])
        slices = verify_ios_app.parse_macho_slices(binary)
        self.assertEqual([slice_.platform for slice_ in slices], [7, 7])
        self.assertEqual([slice_.cputype for slice_ in slices], [verify_ios_app.CPU_TYPE_ARM64, 0x01000007])


if __name__ == "__main__":
    unittest.main()
