"""Verify the actual ELF driver descriptors and the guarded build repair.

Run with Python 3; optionally pass a HAP to verify its packaged library too.
No HarmonyOS device or native library execution is involved.
"""
import hashlib
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'ohos/entry/src/main/cpp/thirdparty/mpv/arm64-v8a/lib/libmpv.so.2'
ORIGINAL = 'daecefe473819a40efc795d2e0cf6916be2c830bc39cb9ccf4251f4c67194d63'
REPAIRED = '7438fcc2aac0e0bbf2f7ed7f04c286efd2a06bc5bcb8c2212a3123fca1f1dff5'


def driver_caps(data):
    assert data[:6] == b'\x7fELF\x02\x01'
    assert struct.unpack_from('<H', data, 18)[0] == 183  # AArch64
    shoff = struct.unpack_from('<Q', data, 40)[0]
    count = struct.unpack_from('<H', data, 60)[0]
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * 64)
                for i in range(count)]

    def offset(address):
        return next(address - s[3] + s[4] for s in sections
                    if s[1] != 8 and s[3] <= address < s[3] + s[5])

    def string(address):
        start = offset(address)
        return data[start:data.index(b'\0', start)]

    relocations = {}
    for section in sections:
        if section[1] == 4:  # SHT_RELA
            for pos in range(section[4], section[4] + section[5], 24):
                address, info, addend = struct.unpack_from('<QQq', data, pos)
                if info & 0xffffffff == 1027:  # R_AARCH64_RELATIVE
                    relocations[address] = addend
    result = {}
    for address, value in relocations.items():
        try:
            name = string(value)
            if name not in (b'ohcodec', b'ohcodec-osd', b'gpu-next'):
                continue
            description = string(relocations[address + 8])
            if not description.startswith((b'HarmonyOS OHCodec', b'Video output based')):
                continue
            # vo_driver: bool encode; int caps; char *name; char *description.
            assert data[offset(address - 8)] == 0
            result[name.decode()] = struct.unpack_from('<I', data, offset(address - 4))[0]
        except (StopIteration, KeyError, ValueError):
            continue
    return result


def main():
    repaired = LIB.read_bytes()
    assert hashlib.sha256(repaired).hexdigest() == REPAIRED
    assert driver_caps(repaired) == {'ohcodec': 4, 'ohcodec-osd': 4, 'gpu-next': 73}
    original = bytearray(repaired)
    for pos in (0x26922dc, 0x2693144):
        original[pos] |= 16
    assert hashlib.sha256(original).hexdigest() == ORIGINAL
    assert driver_caps(original) == {'ohcodec': 20, 'ohcodec-osd': 20, 'gpu-next': 73}
    shell = shutil.which('pwsh') or shutil.which('powershell')
    assert shell
    with tempfile.TemporaryDirectory(prefix='mpv-timing-', dir=ROOT / 'build') as tmp:
        candidate = Path(tmp) / 'libmpv.so.2'
        candidate.write_bytes(original)

        def run(*args):
            return subprocess.run([shell, '-NoProfile', '-File', str(ROOT / 'tool/repair_mpv_timing.ps1'),
                                   '-LibraryPath', str(candidate), *args], capture_output=True)

        assert run('-VerifyOnly').returncode != 0, 'unrepaired library must fail verification'
        assert candidate.read_bytes() == original
        assert run().returncode == 0
        assert candidate.read_bytes() == repaired, 'only the two capability bytes may change'
        assert run().returncode == 0, 'repair must be idempotent'
        assert run('-VerifyOnly').returncode == 0
        candidate.write_bytes(repaired + b'unknown revision')
        assert run().returncode != 0, 'unknown binaries must be rejected before mutation'
        assert candidate.read_bytes() == repaired + b'unknown revision'
    print('PASS: ELF descriptors, exact two-byte repair, idempotence, verification and unknown-library rejection')
    if len(sys.argv) > 1:
        with zipfile.ZipFile(sys.argv[1]) as hap:
            packaged = hap.read('libs/arm64-v8a/libmpv.so.2')
        assert packaged == repaired, 'HAP must contain the repaired library'
        assert driver_caps(packaged)['ohcodec'] == 4
        print('PASS: HAP contains the exact repaired OHCodec library')


if __name__ == '__main__':
    main()
