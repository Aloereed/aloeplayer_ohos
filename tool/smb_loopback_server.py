"""Read-only SMB2 integration fixture. Binds ONLY to IPv4/IPv6 loopback.

Run with build/network-test-venv/Scripts/python.exe. No existing share or device
is used: files are generated underneath build/smb-loopback-data.
"""
from pathlib import Path
import json
import socket
import os
import argparse
from impacket import smbserver
from impacket.ntlm import compute_lmhash, compute_nthash

# Impacket's readOnly branch overwrites O_BINARY after setting it on Windows.
# Restore binary mode for this fixture only (otherwise byte 0x1a becomes EOF).
if os.name == 'nt':
    original_open = os.open
    def binary_open(path, flags, *args, **kwargs):
        return original_open(path, flags | os.O_BINARY, *args, **kwargs)
    os.open = binary_open

parser = argparse.ArgumentParser()
parser.add_argument('--ipv6', action='store_true')
args = parser.parse_args()
address = '::1' if args.ipv6 else '127.0.0.1'
root = Path(__file__).resolve().parents[1] / 'build' / ('smb-loopback-data-v6' if args.ipv6 else 'smb-loopback-data')
root.mkdir(parents=True, exist_ok=True)
(root / 'nested').mkdir(exist_ok=True)
payload = bytes(range(256)) * 32768  # 8 MiB with independently checkable offsets.
(root / 'clip #100% 中文.mkv').write_bytes(payload)
(root / 'nested' / 'sub clip.mkv').write_bytes(payload[:65537])
(root / 'empty.mp4').write_bytes(b'')
with socket.socket(socket.AF_INET6 if args.ipv6 else socket.AF_INET) as probe:
    probe.bind((address, 0))
    port = probe.getsockname()[1]
if args.ipv6:
    smbserver.SMBSERVER.address_family = socket.AF_INET6
server = smbserver.SimpleSMBServer(listenAddress=address, listenPort=port)
server.setSMB2Support(True)
server.addShare('Videos', str(root), 'Read-only test videos', readOnly='yes')
server.addShare('Other', str(root / 'nested'), 'Second read-only share', readOnly='yes')
server.addCredential('fixture', 0, compute_lmhash('fixture-password'), compute_nthash('fixture-password'))
authority = f'[{address}]:{port}' if args.ipv6 else f'{address}:{port}'
(root / 'server.json').write_text(json.dumps({'host': authority, 'username': 'fixture',
    'password': 'fixture-password'}), encoding='utf-8')
print(f'SMB2 fixture on {authority}', flush=True)
server.start()
