#!/usr/bin/env python3
import argparse
import json
import stat
import subprocess
import threading
from pathlib import Path
from urllib.parse import urlsplit

from run_live_native_stream import (
    ROOT,
    install_reverse,
    is_android_emulator,
    make_server,
    remove_reverse,
    require_booted_android_emulator,
    require_booted_ios_simulator,
)

TEST = 'integration_test/live_openaudiomc_test.dart'
FLUTTER = '/Users/cusgadmin/if-local/flutter/bin/flutter'


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config-path', type=Path, required=True)
    parser.add_argument('--device', required=True)
    return parser.parse_args()


def load_session_url(path):
    if not path.is_file():
        raise RuntimeError('configuration file is unavailable')
    if stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise RuntimeError('configuration file must use mode 0600')
    try:
        config = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError('configuration file is unreadable') from error
    if not isinstance(config, dict) or set(config) != {'sessionUrl'}:
        raise RuntimeError('configuration file is invalid')
    session_url = config['sessionUrl']
    if not isinstance(session_url, str) or not session_url:
        raise RuntimeError('configuration file is invalid')
    try:
        parsed = urlsplit(session_url)
        valid = (
            parsed.scheme.lower() == 'https'
            and parsed.hostname == 'session.openaudiomc.net'
            and parsed.username is None
            and parsed.password is None
            and parsed.port in (None, 443)
        )
    except ValueError:
        valid = False
    if not valid:
        raise RuntimeError('configuration file has an invalid session URL')
    return session_url


def main():
    args = parse_args()
    android = is_android_emulator(args.device)
    if android:
        require_booted_android_emulator(args.device)
    else:
        require_booted_ios_simulator(args.device)
    config = {'sessionUrl': load_session_url(args.config_path)}
    server, route = make_server(config)
    reverse = None
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    config_url = f'http://127.0.0.1:{server.server_port}{route}'
    command = [
        FLUTTER,
        'test',
        TEST,
        '-d',
        args.device,
        f'--dart-define=liveAudioConfigUrl={config_url}',
    ]
    try:
        if android:
            reverse = install_reverse(args.device, server.server_port)
        subprocess.run(command, cwd=ROOT, check=True)
    finally:
        try:
            if reverse is not None:
                remove_reverse(args.device, reverse)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    main()
