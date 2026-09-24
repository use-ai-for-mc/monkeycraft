import hashlib
from pathlib import Path
import tempfile
import unittest

from version_web_scripts import version_scripts


class VersionWebScriptsTest(unittest.TestCase):
    def test_changed_program_invalidates_both_cached_scripts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main = root / "main.dart.js"
            bootstrap = root / "flutter_bootstrap.js"
            index = root / "index.html"
            main.write_text("old program")
            bootstrap.write_text('{"mainJsPath":"main.dart.js"}')
            index.write_text('<script src="flutter_bootstrap.js" async></script>')
            version_scripts(root)
            old_bootstrap, old_index = bootstrap.read_text(), index.read_text()
            version_scripts(root)
            self.assertEqual(bootstrap.read_text(), old_bootstrap)
            self.assertEqual(index.read_text(), old_index)
            main.write_text("new program")
            version_scripts(root)
            self.assertNotEqual(bootstrap.read_text(), old_bootstrap)
            self.assertNotEqual(index.read_text(), old_index)
            self.assertIn(hashlib.sha256(main.read_bytes()).hexdigest(), bootstrap.read_text())
            self.assertIn(hashlib.sha256(bootstrap.read_bytes()).hexdigest(), index.read_text())

    def test_unknown_loader_fails_without_modifying_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "main.dart.js").write_text("program")
            bootstrap = root / "flutter_bootstrap.js"
            bootstrap.write_text("unknown loader")
            with self.assertRaises(ValueError):
                version_scripts(root)
            self.assertEqual(bootstrap.read_text(), "unknown loader")


if __name__ == "__main__":
    unittest.main()
