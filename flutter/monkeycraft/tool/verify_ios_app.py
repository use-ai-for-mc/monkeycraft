#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import plistlib
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

CPU_TYPE_ARM64 = 0x0100000C
LC_BUILD_VERSION = 0x32
PLATFORM_IOS = 2
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF


@dataclass(frozen=True)
class MachOSlice:
    cputype: int
    platform: int | None


def parse_macho_slices(data: bytes) -> list[MachOSlice]:
    if len(data) < 4:
        raise ValueError("file is too short")
    magic_be = struct.unpack_from(">I", data)[0]
    if magic_be == FAT_MAGIC:
        if len(data) < 8:
            raise ValueError("truncated fat header")
        count = struct.unpack_from(">I", data, 4)[0]
        if len(data) < 8 + count * 20:
            raise ValueError("truncated fat architecture table")
        offsets = [struct.unpack_from(">IIIII", data, 8 + index * 20)[2] for index in range(count)]
        return [_parse_thin_slice(data, offset) for offset in offsets]
    if magic_be == FAT_MAGIC_64:
        if len(data) < 8:
            raise ValueError("truncated fat header")
        count = struct.unpack_from(">I", data, 4)[0]
        if len(data) < 8 + count * 32:
            raise ValueError("truncated fat architecture table")
        offsets = [struct.unpack_from(">IIQQII", data, 8 + index * 32)[2] for index in range(count)]
        return [_parse_thin_slice(data, offset) for offset in offsets]
    return [_parse_thin_slice(data, 0)]


def _parse_thin_slice(data: bytes, offset: int) -> MachOSlice:
    if offset < 0 or len(data) < offset + 32:
        raise ValueError("truncated Mach-O header")
    magic = struct.unpack_from("<I", data, offset)[0]
    if magic != MH_MAGIC_64:
        raise ValueError("not a 64-bit little-endian Mach-O")
    _, cputype, _, _, command_count, command_size, _, _ = struct.unpack_from("<IiiIIIII", data, offset)
    commands_end = offset + 32 + command_size
    if commands_end > len(data):
        raise ValueError("truncated load commands")
    cursor = offset + 32
    platform: int | None = None
    for _ in range(command_count):
        if cursor + 8 > commands_end:
            raise ValueError("truncated load command")
        command, size = struct.unpack_from("<II", data, cursor)
        if size < 8 or cursor + size > commands_end:
            raise ValueError("invalid load command size")
        if command == LC_BUILD_VERSION:
            if size < 24:
                raise ValueError("truncated LC_BUILD_VERSION")
            platform = struct.unpack_from("<I", data, cursor + 8)[0]
        cursor += size
    return MachOSlice(cputype=cputype & 0xFFFFFFFF, platform=platform)


def is_macho(path: Path) -> bool:
    try:
        data = path.read_bytes()[:4]
    except OSError:
        return False
    if len(data) != 4:
        return False
    return struct.unpack(">I", data)[0] in {FAT_MAGIC, FAT_MAGIC_64} or struct.unpack("<I", data)[0] == MH_MAGIC_64


def bundle_paths(app: Path) -> list[Path]:
    suffixes = {".app", ".appex", ".framework", ".xpc"}
    bundles = [app]
    for directory, names, _ in os.walk(app):
        for name in names:
            path = Path(directory, name)
            if path.suffix in suffixes and path != app:
                bundles.append(path)
    return sorted(set(bundles), key=lambda path: (len(path.parts), str(path)))


def executable_path(bundle: Path) -> Path | None:
    info = bundle / "Info.plist"
    try:
        with info.open("rb") as handle:
            executable = plistlib.load(handle).get("CFBundleExecutable")
    except (OSError, plistlib.InvalidFileException):
        return None
    if not isinstance(executable, str) or executable == "":
        return None
    path = bundle / executable
    return path if path.is_file() else None


def codesign_details(path: Path) -> tuple[int, str]:
    result = subprocess.run(
        ["codesign", "-dvv", str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    return result.returncode, result.stdout + result.stderr


def codesign_verify(path: Path) -> tuple[int, str]:
    result = subprocess.run(
        ["codesign", "--verify", "--strict", "--verbose=2", str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.returncode, result.stdout + result.stderr


def team_identifier(details: str) -> str | None:
    for line in details.splitlines():
        if line.startswith("TeamIdentifier="):
            value = line.partition("=")[2].strip()
            return value if value and value != "not set" else None
    return None


def verify(app: Path) -> list[str]:
    errors: list[str] = []
    if not app.is_dir() or app.suffix != ".app":
        return [f"expected a Runner.app directory: {app}"]
    _, root_details = codesign_details(app)
    expected_team = team_identifier(root_details)
    if expected_team is None:
        errors.append(f"{app}: missing signing TeamIdentifier")
    for bundle in bundle_paths(app):
        code, details = codesign_details(bundle)
        if code != 0:
            errors.append(f"{bundle}: codesign details unavailable")
            continue
        code, _ = codesign_verify(bundle)
        if code != 0:
            errors.append(f"{bundle}: codesign --verify --strict failed")
        team = team_identifier(details)
        if expected_team is not None and team != expected_team:
            errors.append(f"{bundle}: signing team {team or 'missing'} does not match {expected_team}")
    for directory, _, names in os.walk(app):
        for name in names:
            path = Path(directory, name)
            if not is_macho(path):
                continue
            try:
                slices = parse_macho_slices(path.read_bytes())
            except (OSError, ValueError) as error:
                errors.append(f"{path}: cannot parse Mach-O: {error}")
                continue
            for index, slice_ in enumerate(slices):
                if slice_.cputype != CPU_TYPE_ARM64:
                    errors.append(f"{path}: slice {index} is not arm64")
                if slice_.platform != PLATFORM_IOS:
                    errors.append(f"{path}: slice {index} has platform {slice_.platform}, expected iOS device platform 2")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify a signed iOS device Runner.app")
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    errors = verify(args.app.resolve())
    if errors:
        print("iOS app verification failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"iOS app verification passed: {args.app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
