import json
from pathlib import Path
import tempfile
import unittest

from prune_web_renderers import prune_renderers


class PruneWebRenderersTest(unittest.TestCase):
    def prepare(self, root, renderer="canvaskit", target="dart2js"):
        config = {"builds": [{"renderer": renderer, "compileTarget": target}, {}], "useLocalCanvasKit": True}
        (root / "flutter_bootstrap.js").write_text("_flutter.buildConfig = " + json.dumps(config) + ";")
        (root / "flutter_service_worker.js").write_text("self.registration.unregister();")
        for name in ("canvaskit", "chromium/canvaskit", "skwasm", "skwasm_heavy", "wimp"):
            for suffix in (".js", ".wasm", ".js.symbols"):
                path = root / "canvaskit" / (name + suffix)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"renderer fixture")

    def test_keeps_both_browser_variants_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare(root)
            self.assertEqual(len(prune_renderers(root)), 11)
            self.assertEqual(prune_renderers(root), [])
            self.assertEqual(
                {p.relative_to(root).as_posix() for p in (root / "canvaskit").rglob("*") if p.is_file()},
                {"canvaskit/" + stem + suffix for stem in ("canvaskit", "chromium/canvaskit") for suffix in (".js", ".wasm")},
            )

    def test_incompatible_build_or_cache_fails_before_deletion(self):
        for kind in ("wasm", "unknown", "cached", "missing"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.prepare(root, "skwasm" if kind == "wasm" else "canvaskit", "dart2wasm" if kind == "wasm" else "dart2js")
                if kind == "unknown":
                    (root / "flutter_bootstrap.js").write_text("unknown build")
                elif kind == "cached":
                    (root / "flutter_service_worker.js").write_text('const RESOURCES = {"canvaskit/skwasm.wasm": "hash"};')
                elif kind == "missing":
                    (root / "canvaskit/canvaskit.wasm").unlink()
                before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
                with self.assertRaises(ValueError):
                    prune_renderers(root)
                self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})


if __name__ == "__main__":
    unittest.main()
