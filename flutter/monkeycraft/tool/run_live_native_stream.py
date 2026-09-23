#!/usr/bin/env python3
import argparse
import json
import re
import secrets
import stat
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST = 'integration_test/live_native_stream_lan_test.dart'


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config-path', type=Path)
    parser.add_argument('--use-current-prism-config', action='store_true')
    parser.add_argument('--server', required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--reconnect', action='store_true')
    return parser.parse_args()


def current_prism_config():
    return Path.home() / 'Library/Application Support/PrismLauncher/instances/ImagineFun Add-Ons/minecraft/config/monkeycraft.json'


def load_password(path):
    if not path.is_file():
        raise RuntimeError('configuration file is unavailable')
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise RuntimeError('configuration file must not be group or world readable')
    try:
        config = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError('configuration file is unreadable') from error
    password = config.get('password')
    if not isinstance(password, str) or not password:
        raise RuntimeError('configuration file has no password')
    return password


def is_android_emulator(device):
    return re.fullmatch(r'emulator-\d+', device) is not None


def require_booted_ios_simulator(device):
    result = subprocess.run(
        ['xcrun', 'simctl', 'list', 'devices', 'booted', '-j'],
        check=True,
        capture_output=True,
        text=True,
    )
    devices = json.loads(result.stdout).get('devices', {})
    if not any(item.get('udid') == device for items in devices.values() for item in items):
        raise RuntimeError('device is not a booted iOS simulator')


def require_booted_android_emulator(device):
    if not is_android_emulator(device):
        raise RuntimeError('device is not an Android emulator serial')
    state = subprocess.run(
        ['adb', '-s', device, 'get-state'],
        check=True,
        capture_output=True,
        text=True,
    )
    if state.stdout.strip() != 'device':
        raise RuntimeError('Android emulator is not ready')
    boot = subprocess.run(
        ['adb', '-s', device, 'shell', 'getprop', 'sys.boot_completed'],
        check=True,
        capture_output=True,
        text=True,
    )
    if boot.stdout.strip() != '1':
        raise RuntimeError('Android emulator is not booted')


def make_server(config):
    route = '/' + secrets.token_urlsafe(32)
    served = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != route or served.is_set():
                self.send_error(404)
                return
            served.set()
            body = json.dumps(config, separators=(',', ':')).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            return

    server = HTTPServer(('127.0.0.1', 0), Handler)
    return server, route


def reverse_entries(device):
    result = subprocess.run(
        ['adb', '-s', device, 'reverse', '--list'],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.splitlines()


def install_reverse(device, port):
    endpoint = f'tcp:{port}'
    if any(endpoint in entry for entry in reverse_entries(device)):
        raise RuntimeError('temporary Android reverse port is already mapped')
    subprocess.run(
        ['adb', '-s', device, 'reverse', endpoint, endpoint],
        check=True,
        capture_output=True,
        text=True,
    )
    if not any(endpoint in entry for entry in reverse_entries(device)):
        raise RuntimeError('temporary Android reverse mapping was not created')
    return endpoint


def remove_reverse(device, endpoint):
    if any(endpoint in entry for entry in reverse_entries(device)):
        subprocess.run(
            ['adb', '-s', device, 'reverse', '--remove', endpoint],
            check=True,
            capture_output=True,
            text=True,
        )


def main():
    args = parse_args()
    if args.config_path and args.use_current_prism_config:
        raise RuntimeError('choose one configuration source')
    config_path = args.config_path or (current_prism_config() if args.use_current_prism_config else None)
    if config_path is None:
        raise RuntimeError('provide --config-path or --use-current-prism-config')
    android = is_android_emulator(args.device)
    if android:
        require_booted_android_emulator(args.device)
    else:
        require_booted_ios_simulator(args.device)
    config = {
        'server': args.server,
        'password': load_password(config_path),
        'exerciseReconnect': args.reconnect,
    }
    server, route = make_server(config)
    reverse = None
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f'http://127.0.0.1:{server.server_port}{route}'
    command = [
        '/Users/cusgadmin/if-local/flutter/bin/flutter',
        'test',
        TEST,
        '-d',
        args.device,
        f'--dart-define=liveConfigUrl={url}',
    ]
    try:
        if android:
            reverse = install_reverse(args.device, server.server_port)
        subprocess.run(command, cwd=ROOT, check=True)
    finally:
        if reverse is not None:
            remove_reverse(args.device, reverse)
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
