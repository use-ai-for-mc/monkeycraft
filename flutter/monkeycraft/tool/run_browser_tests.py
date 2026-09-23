#!/usr/bin/env python3
"""Run the Flutter browser tests against a local recorded H.264 fixture."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
EXPORT = PROJECT / "tool" / "export_h264_fixture.py"
TESTS = [
    "test/audio/browser_external_audio_service_test.dart",
    "test/browser/browser_notification_backend_web_test.dart",
    "test/browser/browser_reminder_audio_lifecycle_test.dart",
    "test/browser/browser_input_test.dart",
    "test/browser/tailscale_embedded_web_test.dart",
    "test/browser/web_video_test.dart",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flutter", default=os.environ.get("FLUTTER_BIN"))
    parser.add_argument("--fixture", default="streaming-360x640")
    return parser.parse_args()


def flutter_binary(requested: str | None) -> str:
    binary = requested or shutil.which("flutter")
    if binary is None:
        raise RuntimeError("Flutter was not found; pass --flutter or set FLUTTER_BIN")
    return binary


def serve_fixture(path: Path) -> ThreadingHTTPServer:
    body = path.read_bytes()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path != "/fixture.json":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, _format: str, *_args: object) -> None:
            return

    return ThreadingHTTPServer(("127.0.0.1", 0), Handler)


def main() -> None:
    args = parse_args()
    with tempfile.TemporaryDirectory(prefix="monkeycraft-h264-fixture-") as temp:
        fixture = Path(temp) / "fixture.json"
        subprocess.run(
            ["python3", str(EXPORT), "--fixture", args.fixture, "--output", str(fixture)],
            check=True,
            cwd=PROJECT,
        )
        server = serve_fixture(fixture)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            subprocess.run(
                [
                    flutter_binary(args.flutter),
                    "test",
                    "--platform",
                    "chrome",
                    f"--dart-define=VIDEO_FIXTURE_URL=http://127.0.0.1:{server.server_port}/fixture.json",
                    *TESTS,
                ],
                check=True,
                cwd=PROJECT,
            )
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
