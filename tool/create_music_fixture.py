"""Generate only our offline music fixture without rewriting video hardlinks."""
from pathlib import Path
import json
import os
import subprocess
import imageio_ffmpeg

root = Path(__file__).resolve().parents[1]
album = root / 'build/media-server-fixtures/library/Music/Aloe Artist/Aloe Album'
album.mkdir(parents=True, exist_ok=True)
for disc, track, title in [(1, 1, 'Zebra'), (1, 2, 'Alpha'), (2, 1, 'Middle')]:
    target = album / f'{disc}-{track:02} {title}.flac'
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel', 'error',
        '-y', '-f', 'lavfi', '-i', f'sine=frequency={440 + disc * 100 + track * 50}:sample_rate=48000',
        '-t', '12', '-c:a', 'flac', '-metadata', 'artist=Aloe Artist', '-metadata',
        'album_artist=Aloe Artist', '-metadata', 'album=Aloe Album', '-metadata',
        f'title={title}', '-metadata', f'track={track}', '-metadata', f'disc={disc}', str(target)],
        check=True, timeout=30, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
print(json.dumps({'tracks': 3, 'discs': 2, 'album': str(album)}))
