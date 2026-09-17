"""Create an opt-in OHCodec wakeup comparison library; never edit the input."""
import argparse
import hashlib
from pathlib import Path
import struct

BASE_SHA256 = '7438fcc2aac0e0bbf2f7ed7f04c286efd2a06bc5bcb8c2212a3123fca1f1dff5'
CALLBACK_START = 0x13bae94
CALLBACK_SIZE = 392
WAIT_CALL = 0x13b9e04
WAIT_HELPER = CALLBACK_START + 96


def sections(data):
    shoff = struct.unpack_from('<Q', data, 40)[0]
    count = struct.unpack_from('<H', data, 60)[0]
    return [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * 64)
            for i in range(count)]


def offset(data, address):
    return next(s[4] + address - s[3] for s in sections(data)
                if s[1] != 8 and s[3] <= address < s[3] + s[5])


def patch(original):
    if hashlib.sha256(original).hexdigest() != BASE_SHA256:
        raise ValueError('Unknown MPV revision; no output written')
    replacement = Path(__file__).with_name('mpv_ohcodec_wakeup.hex').read_text()
    replacement = bytes.fromhex(replacement)
    if len(replacement) != CALLBACK_SIZE:
        raise ValueError('Invalid callback replacement size')
    data = bytearray(original)
    pos = offset(data, CALLBACK_START)
    data[pos:pos + CALLBACK_SIZE] = replacement
    pos = offset(data, WAIT_CALL)
    if struct.unpack_from('<I', data, pos)[0] != 0x944a6d4f:
        raise ValueError('Input wait instruction mismatch')
    instruction = 0x94000000 | (((WAIT_HELPER - WAIT_CALL) // 4) & 0x3ffffff)
    struct.pack_into('<I', data, pos, instruction)
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.input.resolve() == args.output.resolve():
        raise SystemExit('Refusing to overwrite an existing file')
    data = patch(args.input.read_bytes())
    args.output.write_bytes(data)
    print(f'Patched SHA256: {hashlib.sha256(data).hexdigest()}')
    print('Changed only the input-wait call and two buffer callbacks; EOF/drain logic unchanged')


if __name__ == '__main__':
    main()
