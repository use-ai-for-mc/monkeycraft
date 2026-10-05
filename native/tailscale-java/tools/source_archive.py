#!/usr/bin/env python3
"""Export only source, licenses, fixtures and build definitions; never caches or identities."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parent.parent
top = ['README.md', 'HANDOFF.md', 'INTEGRATION.md', 'TEST_RESULTS.md', 'TESTING.md', 'THIRD_PARTY.md', 'LICENSE-STATUS.md', '.gitignore',
       'dependencies.json', 'minecraft-26.2.json', 'vendor.json']
files = [root / name for name in top]
for directory in ['src', 'licenses', 'examples', 'tools', 'tests', '.github', 'docs']:
    files.extend(p for p in (root / directory).rglob('*')
                 if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc')
entries = {p.relative_to(root).as_posix(): p.read_bytes() for p in files}
for name in entries:
    if name.endswith(('.jar', '.exe', '.dll', '.so', '.dylib')) or Path(name).name in ['identity.json', 'identity.lock']:
        raise SystemExit('Unexpected generated or sensitive payload: ' + name)
manifest = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(entries.items())}
entries['SOURCE-MANIFEST.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
target = root / 'dist/tailscale-java-project.zip'
target.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(target, 'w') as z:
    for name, data in sorted(entries.items()):
        info = zipfile.ZipInfo('tailscale-java/' + name, (2026, 10, 4, 0, 0, 0))
        info.external_attr = 0o100644 << 16
        z.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)
print(json.dumps(dict(file=target.name, files=len(manifest), bytes=target.stat().st_size,
                     sha256=hashlib.sha256(target.read_bytes()).hexdigest()), indent=2))
