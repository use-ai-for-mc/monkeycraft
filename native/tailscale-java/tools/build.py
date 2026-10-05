#!/usr/bin/env python3
"""Reproducible Java build and host-aware distribution. Network is build-time only."""
from pathlib import Path
from collections import defaultdict
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
CACHE = ROOT / '.cache/dependencies'
ROOTS = {
    'org.bouncycastle.crypto.digests.Blake2sDigest',
    'org.bouncycastle.crypto.modes.XChaCha20Poly1305',
    'org.bouncycastle.crypto.params.AEADParameters',
    'org.bouncycastle.crypto.params.KeyParameter',
    'org.bouncycastle.crypto.InvalidCipherTextException',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + '\n', encoding='utf-8')


def java_tool(name):
    executable = name + ('.exe' if os.name == 'nt' else '')
    home = os.environ.get('JAVA_HOME')
    found = str(Path(home) / 'bin' / executable) if home else shutil.which(executable)
    if not found or not Path(found).is_file():
        raise SystemExit('JDK 17+ required; set JAVA_HOME (missing ' + name + ')')
    return found


def restore(row, offline):
    path = CACHE / row['file']
    if path.exists():
        if digest(path) != row['sha256']:
            raise SystemExit('Cached dependency hash mismatch: ' + row['file'])
        return path
    if offline:
        raise SystemExit('Offline dependency missing: ' + row['file'])
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.download')
    try:
        print('Download', row['file'], flush=True)
        with urllib.request.urlopen(row['url'], timeout=60) as response:
            with tmp.open('wb') as output:
                shutil.copyfileobj(response, output)
        if digest(tmp) != row['sha256']:
            raise SystemExit('Downloaded dependency hash mismatch: ' + row['file'])
        tmp.replace(path)
    finally:
        tmp.unlink(missing_ok=True)
    return path


def archive(path, entries):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as z:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (2026, 10, 4, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            z.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)


def subset_bc(row, full):
    output = subprocess.check_output([
        java_tool('jdeps'), '--multi-release', 'base', '-verbose:class', '-filter:none', str(full)
    ], text=True)
    graph = defaultdict(set)
    for line in output.splitlines():
        match = re.match(r'\s+(\S+)\s+->\s+(org\.bouncycastle\.\S+)\s+', line)
        if match:
            graph[match[1]].add(match[2])
    selected, pending = set(), list(ROOTS)
    while pending:
        name = pending.pop()
        if name not in selected:
            selected.add(name)
            pending.extend(graph[name] - selected)
    entries = {
        'META-INF/MANIFEST.MF': b'Manifest-Version: 1.0\r\nImplementation-Title: BC lightweight subset\r\nImplementation-Version: 1.86\r\n\r\n',
        'META-INF/LICENSE-bouncycastle.txt': (ROOT / 'licenses/bcprov-jdk18on-1.86-LICENSE.md.txt').read_bytes(),
    }
    with zipfile.ZipFile(full) as z:
        for name in sorted(selected):
            path = name.replace('.', '/') + '.class'
            entries[path] = z.read(path)
    path = BUILD / 'bc-lightweight-subset-1.86.jar'
    archive(path, entries)
    write_json(BUILD / 'bc-subset.json', dict(
        source=row, roots=sorted(ROOTS), class_count=len(selected),
        classes={k: hashlib.sha256(v).hexdigest() for k, v in entries.items() if k.endswith('.class')},
        method='transitive base-class closure; class bytes unchanged',
        subset_sha256=digest(path)))
    return path


def compile_sources(source, destination, classpath):
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    sources = sorted(source.rglob('*.java'))
    args = BUILD / (destination.name + '-sources.txt')
    args.write_text('\n'.join('"' + p.as_posix() + '"' for p in sources) + '\n', encoding='utf-8')
    subprocess.run([java_tool('javac'), '--release', '17', '-encoding', 'UTF-8',
                    '-cp', os.pathsep.join(map(str, classpath)), '-d', str(destination),
                    '@' + str(args)], check=True)


def main():
    global BUILD
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile', choices=['minecraft-26.2', 'standalone'], default='minecraft-26.2')
    parser.add_argument('--build-dir', type=Path)
    parser.add_argument('--offline', action='store_true', help='do not download build dependencies')
    args = parser.parse_args()
    if args.build_dir:
        BUILD = args.build_dir.resolve()
    BUILD.mkdir(parents=True, exist_ok=True)
    for vendor in json.loads((ROOT / 'vendor.json').read_text()):
        for path, expected in vendor.get('sha256', {}).items():
            if digest(ROOT / path) != expected:
                raise SystemExit('Vendored source hash mismatch: ' + path)
    locked = json.loads((ROOT / 'dependencies.json').read_text())
    bc = next(row for row in locked if row['file'].startswith('bcprov-'))
    subset = subset_bc(bc, restore(bc, args.offline))
    bundled, provided = [subset], []
    profile = None
    if args.profile == 'standalone':
        bundled.extend(restore(row, args.offline) for row in locked if row != bc)
    else:
        profile = json.loads((ROOT / (args.profile + '.json')).read_text())
        for row in profile['provided']:
            group, name, version = row['coordinate'].split(':')
            row = dict(row, url='https://repo.maven.apache.org/maven2/' +
                       group.replace('.', '/') + '/' + name + '/' + version + '/' + row['file'])
            provided.append(restore(row, args.offline))
        bundled.extend(restore(row, args.offline) for row in profile['additional'])
    deps = bundled + provided
    compile_sources(ROOT / 'src/main/java', BUILD / 'classes', deps)
    compile_sources(ROOT / 'src/test/java', BUILD / 'test-classes', [BUILD / 'classes'] + deps)
    compile_sources(ROOT / 'examples', BUILD / 'example-classes', [BUILD / 'classes'] + deps)
    entries = {p.relative_to(BUILD / 'classes').as_posix(): p.read_bytes()
               for p in (BUILD / 'classes').rglob('*.class')}
    entries['META-INF/MANIFEST.MF'] = b'Manifest-Version: 1.0\r\nImplementation-Title: Experimental Java Tailscale client\r\n\r\n'
    for p in (ROOT / 'licenses').iterdir():
        entries['META-INF/licenses/' + p.name] = p.read_bytes()
    library = BUILD / 'tailscale-java.jar'
    archive(library, entries)
    test_cp = [BUILD / 'test-classes', library] + deps
    (BUILD / 'test-classpath.txt').write_text(os.pathsep.join(map(str, test_cp)), encoding='utf-8')
    (BUILD / 'tmp').mkdir(exist_ok=True)
    subprocess.run([java_tool('java'), '-cp', os.pathsep.join(map(str, test_cp)),
                    'com.monkeycraft.tailscale.ProtocolTests',
                    str(ROOT / 'tests/public-crypto-vectors.properties'), str(BUILD / 'tmp')], check=True)
    if (ROOT / 'src/test/java/com/monkeycraft/tailscale/DependencyChecks.java').exists():
        subprocess.run([java_tool('java'), '-cp', os.pathsep.join(map(str, test_cp)),
                        'com.monkeycraft.tailscale.DependencyChecks'], check=True)
    runtime = [dict(file=p.name, sha256=digest(p), size=p.stat().st_size) for p in bundled]
    write_json(BUILD / 'runtime-dependencies.json', runtime)
    package = {'tailscale-java.jar': library.read_bytes()}
    package.update({'lib/' + p.name: p.read_bytes() for p in bundled})
    for name in ['README.md', 'HANDOFF.md', 'INTEGRATION.md', 'TEST_RESULTS.md', 'THIRD_PARTY.md', 'TESTING.md', 'LICENSE-STATUS.md']:
        package[name] = (ROOT / name).read_bytes()
    for p in (ROOT / 'docs').rglob('*'):
        if p.is_file():
            package[p.relative_to(ROOT).as_posix()] = p.read_bytes()
    for name in ['runtime-dependencies.json', 'bc-subset.json']:
        package[name] = (BUILD / name).read_bytes()
    if profile:
        package['host-requirements.json'] = json.dumps(profile, indent=2).encode()
    artifact = (BUILD / 'dist' if args.build_dir else ROOT / 'dist') / ('tailscale-java-' + args.profile + '-libs.zip')
    archive(artifact, package)
    summary = dict(profile=args.profile, java=subprocess.check_output(
        [java_tool('java'), '-version'], stderr=subprocess.STDOUT, text=True).strip(),
        package=artifact.name, size=artifact.stat().st_size, sha256=digest(artifact),
        library_sha256=digest(library), provided=[p.name for p in provided], bundled=runtime)
    write_json(BUILD / 'build-result.json', summary)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
