#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile


ROOT = Path(__file__).resolve().parent
SUPPORTED_ABIS = frozenset(("arm64-v8a", "armeabi-v7a"))
REQUIRED_LIBRARIES = frozenset(("libtailscale_monkeycraft.so", "libtailscale_jni.so"))
PT_LOAD = 1
ELFCLASS64 = 2
ELFDATA2LSB = 1
ELFDATA2MSB = 2


class VerificationError(Exception):
  pass


def fail(message):
  raise VerificationError(message)


def sha256(data):
  return hashlib.sha256(data).hexdigest()


def native_entries(apk):
  entries = {}
  for name in apk.namelist():
    parts = name.split("/")
    if len(parts) == 3 and parts[0] == "lib" and parts[2].endswith(".so"):
      entries.setdefault(parts[1], {})[parts[2]] = name
  return entries


def load_segments(data, name):
  if data[:4] != b"\x7fELF":
    fail(f"{name} is not an ELF file")
  if len(data) < 64:
    fail(f"{name} has a truncated ELF header")
  elf_class = data[4]
  byte_order = data[5]
  if byte_order == ELFDATA2LSB:
    endian = "<"
  elif byte_order == ELFDATA2MSB:
    endian = ">"
  else:
    fail(f"{name} has an unsupported ELF byte order")
  if elf_class == ELFCLASS64:
    header = struct.unpack_from(endian + "HHIQQQIHHHHHH", data, 16)
    program_offset, entry_size, entry_count = header[4], header[8], header[9]
    format_string = endian + "IIQQQQQQ"
    alignment_index = 7
  elif elf_class == 1:
    header = struct.unpack_from(endian + "HHIIIIIHHHHHH", data, 16)
    program_offset, entry_size, entry_count = header[4], header[8], header[9]
    format_string = endian + "IIIIIIII"
    alignment_index = 7
  else:
    fail(f"{name} has an unsupported ELF class")
  expected_size = struct.calcsize(format_string)
  if entry_size < expected_size or program_offset + entry_size * entry_count > len(data):
    fail(f"{name} has an invalid program-header table")
  return [
    struct.unpack_from(format_string, data, program_offset + index * entry_size)[alignment_index]
    for index in range(entry_count)
    if struct.unpack_from(format_string, data, program_offset + index * entry_size)[0] == PT_LOAD
  ]


def verify(apk_path, manifest_path):
  manifest = json.loads(manifest_path.read_text())
  artifacts = manifest.get("artifacts")
  if not isinstance(artifacts, dict) or set(artifacts) != SUPPORTED_ABIS:
    fail("manifest must declare exactly arm64-v8a and armeabi-v7a")
  with zipfile.ZipFile(apk_path) as apk:
    entries = native_entries(apk)
    if set(entries) != SUPPORTED_ABIS:
      fail(f"APK native ABIs must be exactly {sorted(SUPPORTED_ABIS)}, found {sorted(entries)}")
    for abi in sorted(SUPPORTED_ABIS):
      missing = REQUIRED_LIBRARIES - set(entries[abi])
      if missing:
        fail(f"APK is missing {sorted(missing)} for {abi}")
      tailscale = apk.read(entries[abi]["libtailscale_monkeycraft.so"])
      expected = artifacts[abi].get("so", {}).get("sha256")
      if not isinstance(expected, str) or sha256(tailscale) != expected:
        fail(f"libtailscale_monkeycraft.so hash does not match manifest for {abi}")
    for library, entry in entries["arm64-v8a"].items():
      alignments = load_segments(apk.read(entry), entry)
      if not alignments:
        fail(f"{entry} has no PT_LOAD segment")
      if any(alignment < 16 * 1024 for alignment in alignments):
        fail(f"{entry} has a PT_LOAD segment below 16KB alignment: {alignments}")


def main():
  parser = argparse.ArgumentParser(description="Verify MonkeyCraft's packaged Android native libraries")
  parser.add_argument("apk", type=Path)
  parser.add_argument("--manifest", type=Path, default=ROOT / "out" / "MANIFEST.json")
  args = parser.parse_args()
  try:
    verify(args.apk, args.manifest)
  except (OSError, ValueError, zipfile.BadZipFile, VerificationError) as error:
    print(f"APK verification failed: {error}", file=sys.stderr)
    return 1
  print(f"APK verification passed: {args.apk}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
