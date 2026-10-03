import json
from pathlib import Path
import re
import sys


def prune_renderers(root: Path) -> list[str]:
    bootstrap = (root / "flutter_bootstrap.js").read_text()
    match = re.search(r"_flutter\.buildConfig\s*=\s*(\{[^\n]+\});", bootstrap)
    if match is None:
        raise ValueError("unknown Flutter build configuration")
    config = json.loads(match[1])
    builds = [build for build in config.get("builds", []) if build]
    if not builds or any(
        build.get("compileTarget") != "dart2js"
        or build.get("renderer") != "canvaskit"
        for build in builds
    ):
        raise ValueError("renderer pruning requires a CanvasKit-only dart2js build")
    if config.get("useLocalCanvasKit") is not True:
        raise ValueError("renderer pruning requires local CanvasKit assets")
    for relative in (
        "canvaskit/canvaskit.js",
        "canvaskit/canvaskit.wasm",
        "canvaskit/chromium/canvaskit.js",
        "canvaskit/chromium/canvaskit.wasm",
    ):
        path = root / relative
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing required renderer: {relative}")
    candidates = [
        root / "canvaskit" / (stem + suffix)
        for stem in ("skwasm", "skwasm_heavy", "wimp")
        for suffix in (".js", ".wasm", ".js.symbols")
    ] + [
        root / "canvaskit/canvaskit.js.symbols",
        root / "canvaskit/chromium/canvaskit.js.symbols",
    ]
    worker = (root / "flutter_service_worker.js").read_text()
    for path in candidates:
        if path.relative_to(root).as_posix() in worker:
            raise ValueError("service worker still references a pruned renderer")
    removed = []
    for path in candidates:
        if path.is_file():
            removed.append(path.relative_to(root).as_posix())
            path.unlink()
    return removed


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: prune_web_renderers.py RELEASE_DIRECTORY")
    removed = prune_renderers(Path(sys.argv[1]))
    print(f"Removed {len(removed)} unused Flutter renderer assets")
