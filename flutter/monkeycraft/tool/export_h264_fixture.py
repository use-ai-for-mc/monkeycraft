#!/usr/bin/env python3
"""Export recorded MonkeyCraft H.264 access units for Flutter's browser test."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[3]
FIXTURES = REPOSITORY / "web" / "test" / "fixtures"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", default="streaming-360x640")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def load_access_units(name: str) -> list[str]:
    fixture = FIXTURES / name
    if fixture.parent != FIXTURES or not fixture.is_dir():
        raise RuntimeError(f"unknown fixture: {name}")
    binary = (fixture / "binary.bin").read_bytes()
    units: list[str] = []
    for raw_line in (fixture / "session.jsonl").read_text().splitlines():
        line = json.loads(raw_line)
        entry = line.get("bin")
        if line.get("dir") != "in" or not isinstance(entry, dict):
            continue
        if entry.get("kind") != "video":
            continue
        offset = entry.get("offset")
        length = entry.get("length")
        if not isinstance(offset, int) or not isinstance(length, int):
            raise RuntimeError("fixture contains a malformed binary offset")
        frame = binary[offset : offset + length]
        if len(frame) != length:
            raise RuntimeError("fixture binary frame is truncated")
        if entry.get("header") is not None:
            if len(frame) < 6 or frame[:2] != b"MC":
                raise RuntimeError("fixture IDR frame has an invalid MonkeyCraft header")
            frame = frame[6:]
        units.append(base64.b64encode(frame).decode("ascii"))
    if len(units) < 40:
        raise RuntimeError("fixture does not contain enough video access units")
    return units


def main() -> None:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(load_access_units(args.fixture), separators=(",", ":")))


if __name__ == "__main__":
    main()
