#!/usr/bin/env python3
"""Encode the reviewed owner-provided iPhone recording as README demos. Requires ffmpeg/ffprobe."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIPS = [('keyboard', 1.35, 3.10), ('scroll', 3.10, 7.216667)]


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='Reviewed 1320x2868 physical-iPhone recording')
    args = parser.parse_args()
    probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height:format=duration', '-of', 'json', str(args.source)]))
    stream = probe['streams'][0]
    if (stream['width'], stream['height']) != (1320, 2868):
        parser.error('This edit recipe expects the reviewed 1320x2868 recording; review the crop and intervals for other captures.')
    if float(probe['format']['duration']) < 7.20:
        parser.error('Source is shorter than the reviewed gesture sequence.')
    assets = ROOT / 'docs/media'
    assets.mkdir(parents=True, exist_ok=True)
    movie = assets / 'demo.mp4'
    run('ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(args.source),
        '-map', '0:v:0', '-an', '-map_metadata', '-1', '-vf',
        'crop=1320:2548:0:320,setpts=PTS-STARTPTS,fps=60:round=near,scale=660:1274:flags=lanczos,setsar=1',
        '-c:v', 'libx264', '-crf', '19', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(movie))
    for name, start, end in CLIPS:
        run('ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(movie), '-vf',
            f'trim=start={start}:end={end},setpts=PTS-STARTPTS,fps=50,scale=320:-2:flags=lanczos,split[a][b];'
            '[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3',
            '-loop', '0', str(assets / f'{name}.gif'))
    provenance = {
        'recorded_on': '2026-11-11', 'application': 'MessageMotion example in a local sandbox host',
        'source': 'Owner-provided physical iPhone screen recording',
        'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
        'source_dimensions': [1320, 2868], 'source_duration_seconds': float(probe['format']['duration']),
        'crop_pixels': {'x': 0, 'y': 320, 'width': 1320, 'height': 2548},
        'crop_reason': 'Remove only system status and host back-navigation UI; retain the component header, transcript, composer and keyboard.',
        'data': 'Local in-memory example fixtures; no Apple Messages footage or production conversations.',
        'speed': 1, 'audio': 'removed', 'source_metadata': 'not copied',
        'edits': 'Crop, trim, timestamp normalization, scaling, frame-rate quantization and GIF palette compression. No speed changes, synthetic interpolation, replaced UI or simulated gestures.',
        'distributed_media': ['scroll.gif', 'keyboard.gif', 'demo.mp4'],
        'full_video': {'file': 'demo.mp4', 'fps': 60, 'dimensions': [660, 1274], 'silent': True},
        'gif_fps': 50, 'gif_width': 320,
        'endpoint_note': 'CFR/GIF endpoint quantization may vary a clip boundary by one frame; gesture playback is not retimed.',
        'clips': [{'demo': name, 'source_start_seconds': start, 'source_end_seconds': end} for name, start, end in CLIPS]
    }
    (assets / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')


if __name__ == '__main__':
    main()
