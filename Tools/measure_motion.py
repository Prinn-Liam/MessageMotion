#!/usr/bin/env python3
"""Estimate bubble gaps from a vertical stripe of a synthetic/non-private recording.

Python standard library only; ffmpeg/ffprobe are optional external analysis tools.
Tracking is heuristic. Read docs/MEASUREMENT.md before interpreting the output.
"""
import argparse
import json
import shutil
import statistics
import subprocess
from pathlib import Path


def bands(mask, top, bottom, minimum_height=40, join_gap=12):
    result = []
    y = top
    while y < bottom:
        if not mask[y]:
            y += 1
            continue
        end = y + 1
        while end < bottom and mask[end]:
            end += 1
        if result and y - result[-1][1] <= join_gap:
            result[-1] = (result[-1][0], end)
        else:
            result.append((y, end))
        y = end
    return [item for item in result if item[1] - item[0] >= minimum_height]


def match_rows(previous, previous_ids, current, top, bottom, max_shift=230):
    if not previous or not current:
        start = (max(previous_ids) + 1) if previous_ids else 0
        return list(range(start, start + len(current))), 0
    best = None
    for offset in range(-len(previous), len(current) + 1):
        pairs = [(i, i + offset) for i in range(len(previous)) if 0 <= i + offset < len(current)]
        if not pairs:
            continue
        shifts = []
        penalty = 0
        full_count = 0
        for i, j in pairs:
            a, b = previous[i], current[j]
            full = a[0] > top and a[1] < bottom and b[0] > top and b[1] < bottom
            if full:
                full_count += 1
                if abs((a[1] - a[0]) - (b[1] - b[0])) > 4:
                    penalty += 1000
                shifts.append(b[0] - a[0])
            else:
                shifts.append(b[1] - a[1] if a[0] <= top or b[0] <= top else b[0] - a[0])
        shift = statistics.median(shifts)
        cost = penalty + abs(shift) + statistics.mean(abs(x - shift) for x in shifts) * 3
        cost += 0 if full_count else 500
        cost += 0 if abs(shift) <= max_shift else 5000
        if best is None or cost < best[0]:
            best = (cost, offset, shift)
    _, offset, shift = best
    known = next((j, previous_ids[j - offset]) for j in range(len(current)) if 0 <= j - offset < len(previous))
    return [known[1] + j - known[0] for j in range(len(current))], shift


def sample_metrics(rows, ids, shift, frame, fps, scale, normal_gap, top, bottom):
    gaps = []
    for i, (upper, lower) in enumerate(zip(rows, rows[1:])):
        if upper[0] <= top or lower[1] >= bottom:
            continue
        gap = (lower[0] - upper[1]) / scale
        gaps.append({"upper_track": ids[i], "position_points": (upper[1] + lower[0]) / (2 * scale),
                     "gap_points": gap, "deviation_points": gap - normal_gap})
    return {"frame": frame, "time_seconds": frame / fps,
            "estimated_scroll_points_per_second": shift * fps / scale, "gaps": gaps}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("--x", type=int, required=True, help="Stripe left edge in source pixels, inside bubbles")
    parser.add_argument("--top", type=int, required=True, help="First chat pixel, excluding header")
    parser.add_argument("--bottom", type=int, required=True, help="Last chat pixel, excluding composer")
    parser.add_argument("--scale", type=float, required=True, help="Source pixels per UIKit point")
    parser.add_argument("--normal-gap", type=float, required=True, help="Manually measured resting gap in points")
    parser.add_argument("--background", default="255,255,255", help="Background RGB")
    parser.add_argument("--threshold", type=int, default=24)
    parser.add_argument("--fps", type=float, default=60, help="Resample rate, not a claim about source refresh rate")
    parser.add_argument("--minimum-height", type=int, default=40)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        parser.error("Install ffmpeg/ffprobe separately to analyze recordings; the iOS library does not need them")
    background = tuple(int(x) for x in args.background.split(","))
    if len(background) != 3 or any(x < 0 or x > 255 for x in background) or args.scale <= 0 or args.fps <= 0:
        parser.error("RGB requires three values in0...255; scale and fps must be positive")
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                            "-of", "json", str(args.video)], capture_output=True, text=True, check=True)
    stream = json.loads(probe.stdout)["streams"][0]
    height, width = stream["height"], stream["width"]
    if not (0 <= args.x <= width - 6 and 0 <= args.top < args.bottom <= height):
        parser.error("Stripe and viewport must lie inside the video. Inspect its stored orientation first")
    command = ["ffmpeg", "-v", "error", "-noautorotate", "-i", str(args.video), "-vf",
               f"fps={args.fps},crop=6:{height}:{args.x}:0", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    rows, ids, output = [], [], []
    size = 6 * height * 3
    frame = 0
    try:
        while True:
            raw = process.stdout.read(size)
            if len(raw) != size:
                break
            mask = [sum(abs(raw[y * 18 + 9 + c] - background[c]) for c in range(3)) > args.threshold for y in range(height)]
            current = bands(mask, args.top, args.bottom, minimum_height=args.minimum_height)
            ids, shift = match_rows(rows, ids, current, args.top, args.bottom)
            output.append(sample_metrics(current, ids, shift, frame, args.fps, args.scale, args.normal_gap, args.top, args.bottom))
            rows = current
            frame += 1
    finally:
        process.stdout.close()
        status = process.wait()
    if status:
        raise SystemExit(status)
    result = {"schema": 1, "fps_resampled": args.fps, "pixels_per_point": args.scale,
              "normal_gap_points": args.normal_gap, "tracking": "heuristic stripe matching; manually inspect identity and orientation",
              "rows": output}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Wrote {len(output)} resampled frames to {args.output}")


if __name__ == "__main__":
    main()
