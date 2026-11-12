#!/usr/bin/env python3
"""Encode reviewed example captures as README GIFs. Requires optional maintainer tool ffmpeg."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scroll-source', type=Path, required=True)
    parser.add_argument('--keyboard-source', type=Path, required=True)
    args = parser.parse_args()
    assets = ROOT / 'docs/media'
    assets.mkdir(parents=True, exist_ok=True)
    entries = []
    with tempfile.TemporaryDirectory(prefix='messagemotion-gif-') as working:
        for name, source, start, duration in [('scroll', args.scroll_source, 1.6, 4.6), ('keyboard', args.keyboard_source, 5.6, 6.7)]:
            movie = Path(working) / f'{name}.mp4'
            run('ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(source), '-vf',
                f'trim=start={start}:duration={duration},setpts=PTS-STARTPTS,fps=30,scale=600:-2:flags=lanczos,setsar=1',
                '-an', '-c:v', 'libx264', '-crf', '21', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(movie))
            run('ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(movie), '-vf',
                'fps=25,scale=360:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3',
                '-loop', '0', str(assets / f'{name}.gif'))
            entries.append({'demo': name, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                            'source_start_seconds': start, 'source_duration_seconds': duration,
                            'speed': 1, 'intermediate_mp4_fps': 30, 'gif_fps': 25})
    (assets / 'provenance.json').write_text(json.dumps({
        'recorded_on': '2026-11-11', 'application': 'MessageMotionDemo',
        'device': 'iPhone 18 Pro Simulator', 'system': 'iOS 27.2',
        'data': 'Local in-memory example fixtures. No production accounts or Apple Messages footage.',
        'distributed_media': ['scroll.gif', 'keyboard.gif'],
        'edits': 'Trim, timestamp normalization, frame-rate conversion, scaling and palette compression. No retiming, frame interpolation, replacement UI or synthetic motion.',
        'clips': entries}, indent=2) + '\n')


if __name__ == '__main__':
    main()
