"""Compare a debug HAP's MPV against an explicitly selected original ELF."""
import argparse
import hashlib
from pathlib import Path
import zipfile

from test_mpv_timing_patch import loaded_sections


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=Path)
    parser.add_argument('hap', type=Path)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    original = args.library.read_bytes()
    if hashlib.sha256(original).hexdigest() != args.sha256.lower():
        raise SystemExit('FAIL: original library SHA256 mismatch')
    with zipfile.ZipFile(args.hap) as hap:
        packaged = hap.read('libs/arm64-v8a/libmpv.so.2')
    for data in (original, packaged):
        if data[:6] != b'\x7fELF\x02\x01' or data[18:20] != b'\xb7\x00':
            raise SystemExit('FAIL: expected little-endian AArch64 ELF64')
    expected = loaded_sections(original)
    if not expected or loaded_sections(packaged) != expected:
        raise SystemExit('FAIL: packaged MPV runtime sections differ from original')
    print(f'PASS: {len(expected)} runtime sections match original MPV; only non-runtime stripping allowed')
    print(f'Original SHA256: {args.sha256.lower()}')
    print(f'Packaged SHA256: {hashlib.sha256(packaged).hexdigest()}')


if __name__ == '__main__':
    main()
