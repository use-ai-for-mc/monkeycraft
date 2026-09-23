#!/usr/bin/env python3
"""Reject incomplete or non-self-contained Flutter Web release trees."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from html.parser import HTMLParser
from pathlib import Path


REQUIRED_FILES = (
    "index.html",
    "flutter.js",
    "flutter_bootstrap.js",
    "main.dart.js",
    "flutter_service_worker.js",
    "version.json",
    "manifest.json",
    "favicon.png",
    "assets/AssetManifest.bin",
    "assets/FontManifest.json",
    "canvaskit/canvaskit.js",
    "canvaskit/canvaskit.wasm",
    "canvaskit/chromium/canvaskit.js",
    "canvaskit/chromium/canvaskit.wasm",
    "icons/Icon-192.png",
    "icons/Icon-512.png",
    "vendor/jsQR-1.4.0.js",
    "vendor/jsQR-1.4.0.LICENSE",
    "vendor/jsQR-1.4.0.NOTICE",
    "reminder-sw.js",
)


class _IndexParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.base_hrefs: list[str] = []
        self.script_sources: list[str] = []
        self.resource_urls: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "base" and values.get("href") is not None:
            self.base_hrefs.append(values["href"])
        if tag == "script" and values.get("src") is not None:
            self.script_sources.append(values["src"])
        for attribute in ("src", "href"):
            value = values.get(attribute)
            if value is not None:
                self.resource_urls.append(value)


def _fail(message: str) -> None:
    raise ValueError(message)


def _validate_no_links(root: Path) -> None:
    if root.is_symlink():
        _fail("release root must not be a symbolic link")
    for directory, dirs, files in os.walk(root, followlinks=False):
        directory_path = Path(directory)
        for name in [*dirs, *files]:
            path = directory_path / name
            relative = path.relative_to(root)
            if path.is_symlink():
                _fail(f"release must not contain symbolic links: {relative}")



def verify_release(root: Path, base_href: str) -> None:
    if not root.is_dir():
        _fail(f"release directory does not exist: {root}")
    if not re.fullmatch(r"/(?:[^/]+/)*|/", base_href):
        _fail(f"invalid expected base href: {base_href}")

    _validate_no_links(root)
    tailscale = root / "tailscale"
    if tailscale.exists():
        expected = {"worker.js", "rpc.js", "fake-backend.js", "state-store.js", "main.wasm", "wasm_exec.js", "VERSION.json", "LICENSE"}
        if {p.name for p in tailscale.iterdir()} != expected:
            _fail("Tailscale bundle must contain only production runtime assets")
        version = json.loads((tailscale / "VERSION.json").read_text())
        for name, key in (("main.wasm", "wasm"), ("wasm_exec.js", "wasmExec")):
            if hashlib.sha256((tailscale / name).read_bytes()).hexdigest() != version[key]["sha256"]:
                _fail(f"Tailscale runtime hash mismatch: {name}")
    for relative in REQUIRED_FILES:
        path = root / relative
        if not path.is_file() or path.stat().st_size == 0:
            _fail(f"Flutter Web build is missing non-empty {relative}")

    index = (root / "index.html").read_text(encoding="utf-8")
    if "$FLUTTER_BASE_HREF" in index:
        _fail("index.html still contains Flutter base-href placeholder")
    parser = _IndexParser()
    parser.feed(index)
    if parser.base_hrefs != [base_href]:
        _fail(f"index.html base href must be exactly {base_href!r}")
    if "vendor/jsQR-1.4.0.js" not in parser.script_sources:
        _fail("index.html must load local vendor/jsQR-1.4.0.js")
    for url in parser.resource_urls:
        if url.startswith(("http://", "https://", "//")):
            _fail(f"index.html must not reference a remote resource: {url}")
    if re.search(r"(?:cdnjs|unpkg|jsdelivr)", index, flags=re.IGNORECASE):
        _fail("index.html must not reference a CDN")

    for relative in ("manifest.json", "assets/FontManifest.json", "version.json"):
        try:
            json.loads((root / relative).read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            _fail(f"{relative} is not valid JSON: {error.msg}")

    font_manifest = json.loads((root / "assets/FontManifest.json").read_text())
    manifest = json.loads((root / "manifest.json").read_text())
    assets = [
        "assets/" + font["asset"]
        for family in font_manifest
        for font in family["fonts"]
    ] + [icon["src"] for icon in manifest["icons"]]
    for relative in assets:
        path = root / relative
        if not path.resolve().is_relative_to(root.resolve()):
            _fail(f"manifest resource must stay within release: {relative}")
        if not path.is_file() or path.stat().st_size == 0:
            _fail(f"manifest references missing or empty resource: {relative}")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: verify_web_release.py RELEASE_DIRECTORY BASE_HREF", file=sys.stderr)
        return 2
    try:
        verify_release(Path(sys.argv[1]).absolute(), sys.argv[2])
    except ValueError as error:
        print(f"Flutter Web release validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
