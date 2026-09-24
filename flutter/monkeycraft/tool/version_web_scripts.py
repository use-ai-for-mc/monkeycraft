import hashlib
from pathlib import Path
import re
import sys


def version_scripts(root: Path) -> None:
    main_hash = hashlib.sha256((root / "main.dart.js").read_bytes()).hexdigest()
    bootstrap = root / "flutter_bootstrap.js"
    source, count = re.subn(
        r'"mainJsPath":"main\.dart\.js(?:\?v=[a-f0-9]+)?"',
        f'"mainJsPath":"main.dart.js?v={main_hash}"',
        bootstrap.read_text(),
    )
    if count != 1:
        raise ValueError("Expected exactly one Flutter JavaScript entrypoint")
    bootstrap_hash = hashlib.sha256(source.encode()).hexdigest()
    index = root / "index.html"
    html, count = re.subn(
        r'src="flutter_bootstrap\.js(?:\?v=[a-f0-9]+)?"',
        f'src="flutter_bootstrap.js?v={bootstrap_hash}"',
        index.read_text(),
    )
    if count != 1:
        raise ValueError("Expected exactly one Flutter bootstrap script")
    bootstrap.write_text(source)
    index.write_text(html)


if __name__ == "__main__":
    version_scripts(Path(sys.argv[1]))
