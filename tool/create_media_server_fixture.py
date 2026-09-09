"""Generate deterministic, offline-only media libraries for real server tests."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'build' / 'media-server-fixtures' / 'library'
MOVIE = DATA / 'Movies' / 'Aloe Movie (2026)'
SHOW = DATA / 'Shows' / 'Aloe Show'
MOVIE.mkdir(parents=True, exist_ok=True)
(SHOW / 'Season 01').mkdir(parents=True, exist_ok=True)
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0

def run(arguments):
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', *arguments],
                   check=True, timeout=60, creationflags=flags)

high = MOVIE / 'Aloe Movie (2026) - High.mkv'
run(['-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=25',
     '-f', 'lavfi', '-i', 'sine=frequency=880:sample_rate=48000',
     '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
     '-t', '24', '-map', '0:v', '-map', '1:a', '-map', '2:a',
     '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-g', '25',
     '-c:a', 'aac', '-b:a', '96k', '-metadata:s:a:0', 'language=eng',
     '-metadata:s:a:1', 'language=zho', str(high)])
run(['-i', str(high), '-t', '24', '-map', '0:v', '-map', '0:a:0',
     '-vf', 'scale=160:90', '-c:v', 'libx264', '-preset', 'ultrafast',
     '-c:a', 'copy', str(MOVIE / 'Aloe Movie (2026) - Low.mkv')])
(MOVIE / 'movie.nfo').write_text('<movie><title>Aloe Fixture Movie</title><year>2026</year>'
    '<plot>Local generated compatibility fixture.</plot><genre>Test</genre><rating>8.5</rating></movie>', encoding='utf-8')
for language, text in [('eng', 'English fixture subtitle'), ('zho', '中文字幕测试')]:
    (MOVIE / f'{high.stem}.{language}.srt').write_text(
        f'1\n00:00:01,000 --> 00:00:05,000\n{text}\n', encoding='utf-8')
(SHOW / 'tvshow.nfo').write_text('<tvshow><title>Aloe Fixture Show</title><year>2026</year>'
    '<plot>Offline episode fixture.</plot></tvshow>', encoding='utf-8')
for episode in range(1, 4):
    target = SHOW / 'Season 01' / f'Aloe Show S01E{episode:02}.mkv'
    if not target.exists():
        try:
            os.link(high, target)
        except OSError:
            shutil.copyfile(high, target)
    target.with_suffix('.nfo').write_text(f'<episodedetails><title>Fixture Episode {episode}</title>'
        f'<season>1</season><episode>{episode}</episode><plot>Local test episode.</plot></episodedetails>', encoding='utf-8')
print(json.dumps({'library': str(DATA), 'seconds': 24, 'versions': 2,
                  'audioTracks': 2, 'externalSubtitles': 2, 'episodes': 3}))
