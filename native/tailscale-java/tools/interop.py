#!/usr/bin/env python3
"""Run isolated Go/official-client interoperability tests; never reads a personal tailnet."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
LAB = ROOT / 'tests/interop'


def main():
    global BUILD
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-dir', type=Path)
    parser.add_argument('--recovery', action='store_true', help='include IPv6 and direct/DERP recovery')
    parser.add_argument('--streams', action='store_true', help='include concurrent bulk streams, slow readers and half-close')
    args = parser.parse_args()
    if args.build_dir:
        BUILD = args.build_dir.resolve()
    if os.name == 'nt':
        raise SystemExit('Official-daemon lab currently requires Unix sockets; protocol tests support Windows.')
    cp = (BUILD / 'test-classpath.txt').read_text(encoding='utf-8')
    env = os.environ.copy()
    for key in ['TS_AUTHKEY', 'TS_AUTH_KEY', 'TS_CLIENT_SECRET', 'TS_CLIENT_ID',
                'TS_ID_TOKEN', 'TS_AUDIENCE', 'TS_CONTROL_URL']:
        env.pop(key, None)
    env['TS_NO_LOGS_NO_SUPPORT'] = 'true'
    env['CGO_ENABLED'] = '0'
    env['GOTOOLCHAIN'] = 'local'
    for key, path in [('GOPATH', ROOT / '.cache/gopath'), ('GOCACHE', ROOT / '.cache/go-build')]:
        env.setdefault(key, str(path))
    env.setdefault('GOMODCACHE', str(Path(env['GOPATH']) / 'pkg/mod'))
    for key in ['GOTMPDIR', 'TMPDIR']:
        env[key] = str(Path(env.get('TSJAVA_TEST_TMP', str(BUILD / 'tmp'))).resolve())
    for key in ['GOPATH', 'GOCACHE', 'GOMODCACHE', 'GOTMPDIR']:
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    go = env.get('GO_BIN') or shutil.which('go')
    if not go:
        raise SystemExit('Go 1.26.6 is required for test peers only; set GO_BIN.')
    version = subprocess.check_output([go, 'env', 'GOVERSION'], env=env, text=True).strip()
    if version != 'go1.26.6':
        raise SystemExit('Test fixture requires exactly Go 1.26.6, found ' + version)
    jhome = env.get('JAVA_HOME')
    java = str(Path(jhome) / 'bin/java') if jhome else shutil.which('java')
    if not java:
        raise SystemExit('Java not found')
    env['RESEARCH_JAVA'] = java
    env['RESEARCH_JAVA_CP'] = cp
    env['RESEARCH_OFFICIAL'] = str(BUILD / 'official-tailscaled')
    env['RESEARCH_RECOVERY'] = '1' if args.recovery else '0'
    env['RESEARCH_STRESS'] = '1' if args.streams else '0'
    logs = BUILD / 'test-results'
    logs.mkdir(exist_ok=True)

    def run(name, command, timeout=300):
        print(name, flush=True)
        with (logs / (name + '.log')).open('w') as log:
            result = subprocess.run(command, cwd=LAB, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            raise SystemExit(name + ' FAILED; see build/test-results/' + name + '.log')

    run('modules', [go, 'mod', 'verify'])
    for name, target in [('control-lab', './cmd/java-control-lab'),
                         ('wg-lab', './cmd/java-wg-lab'),
                         ('official-tailscaled', 'tailscale.com/cmd/tailscaled')]:
        run('build-' + name, [go, 'build', '-trimpath', '-o', str(BUILD / name), target])
    run('control', [str(BUILD / 'control-lab'), java, cp])
    run('wireguard', [str(BUILD / 'wg-lab'), java, cp])
    for mode in ['direct', 'derp']:
        env['RESEARCH_PATH'] = mode
        run(mode, [go, 'test', '-tags', 'integration', './internal/javatest',
                   '-run', 'TestJavaClient', '-count=1', '-v'])
    print('INTEROP_PASS control + WireGuard + official-client direct/DERP + identity lifecycle', flush=True)


if __name__ == '__main__':
    main()
