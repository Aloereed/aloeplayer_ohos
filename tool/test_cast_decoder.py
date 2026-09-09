"""Generate AES-128 HLS and compare decoded audio/video hashes through the relay.
Only loopback networking is used. The desktop decoder is a test dependency,
never an app artifact. Install tool/cast-test-requirements.txt in the test venv.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'build' / 'cast-hls-fixture'
DATA.mkdir(exist_ok=True)
VARIANT = DATA / 'variant'
VARIANT.mkdir(exist_ok=True)
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
DART = os.environ.get('CAST_TEST_DART', 'E:/source/flutter_327/bin/dart.bat')
FLAGS = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0

def run(args, timeout=40):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True,
                            timeout=timeout, creationflags=FLAGS)
    if result.returncode:
        raise RuntimeError(result.stderr[-6000:])
    return result.stdout.strip()

key = VARIANT / 'key.bin'
key.write_bytes(bytes(range(16)))
info = DATA / 'key-info.txt'
info.write_text('key.bin\n' + key.as_posix() + '\n', encoding='utf-8')
run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y',
     '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=25',
     '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000',
     '-t', '4', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-g', '25', '-sc_threshold', '0',
     '-c:a', 'aac', '-b:a', '96k', '-hls_time', '1', '-hls_playlist_type', 'vod',
     '-hls_key_info_file', str(info), '-hls_segment_filename', str(VARIANT / 'segment%02d.ts'),
     str(VARIANT / 'video.m3u8')])
master = DATA / 'master.m3u8'
master.write_text('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nvariant/video.m3u8\n', encoding='utf-8')
assert '#EXT-X-KEY:METHOD=AES-128' in (VARIANT / 'video.m3u8').read_text()

def decode(source, seek=None):
    args = [FFMPEG, '-hide_banner', '-loglevel', 'error', '-nostdin',
            '-protocol_whitelist', 'file,http,https,tcp,tls,crypto', '-allowed_extensions', 'ALL']
    if seek is not None:
        args += ['-ss', str(seek)]
    args += ['-i', source, '-map', '0:v:0', '-map', '0:a:0',
             '-c:v', 'rawvideo', '-c:a', 'pcm_s16le', '-f', 'streamhash', '-hash', 'sha256', '-']
    output = run(args)
    assert len(output.splitlines()) == 2, output
    return output

server = subprocess.Popen([DART, 'tool/serve_cast_fixture.dart', str(DATA)], cwd=ROOT,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, creationflags=FLAGS)
try:
    line = server.stdout.readline()
    if not line:
        raise RuntimeError(server.stderr.read())
    url = json.loads(line)['url']
    assert url.startswith('http://127.0.0.1:')
    results = []
    for seek in (None, 1.25):
        expected = decode(str(master), seek)
        actual = decode(url, seek)
        assert actual == expected, f'decoded hash mismatch: {expected!r} != {actual!r}'
        results.append({'seekSeconds':seek, 'decodedStreams': actual.splitlines()})
    print(json.dumps({'result':'PASS', 'fixture':'4 seconds H.264/AAC AES-128 HLS',
                      'checks':results}, ensure_ascii=False))
finally:
    try:
        out, err = server.communicate('quit\n', timeout=10)
        if out.strip(): print(out.strip())
        if server.returncode: print(err[-2000:], file=sys.stderr)
    except subprocess.TimeoutExpired:
        server.kill(); server.communicate()
