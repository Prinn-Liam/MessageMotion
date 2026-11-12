# Measuring motion from recordings

Use recordings of synthetic conversations. No reference Messages recording or private conversation is distributed with this project. Python3 and separately installed `ffmpeg`/`ffprobe` are only needed for this analysis tool, not the library or demo.

The original investigation sampled a six-pixel vertical stripe through bubble interiors. Background-color thresholding found each bubble's top/bottom edges; neighboring frames were matched by height and bounded translation. Gap deviations and estimated scroll motion were then compared across slow drag, fast drag, momentum, contact and keyboard sequences.

The included tool makes the recording geometry explicit instead of using device-specific hard-coded paths:

```sh
python3 Tools/measure_motion.py synthetic-recording.mov \
  --x 300 --top 400 --bottom 2500 \
  --scale 3 --normal-gap 16 --background 255,255,255 \
  --fps 60 --output measurement.json

python3 -m unittest discover -s Tools -p 'test_measure.py'
```

Replace every geometry value for your recording. `--x`, top and bottom are **source pixels**; scale is pixels per UIKit point; normal-gap is your manually measured static gap in **points**. Choose a stripe inside both participants' bubbles. Tails, rounded edges, text-only intersections, separators, keyboards, translucency and similar bubble/background colors can corrupt segmentation. Set a background/threshold suited to the actual appearance.

The tool reads the stored orientation without autorotation. It resamples to the requested fps and streams a stripe through ffmpeg, then writes JSON containing frame/time, estimated motion and visible gap deviations. Resampled timestamps are not original display presentation timestamps. Scroll speed is estimated from the median matched bubble translation, which also includes deformation; it is not a direct contentOffset measurement.

Tracking is a heuristic. Repeated equal-height bubbles, very large per-frame movement and entering/leaving partial rows can make identity ambiguous. Inspect the recording against the output before drawing conclusions. Do not treat every generated track as ground truth or infer exact private spring parameters from it.

For comparisons, use the same display scale, recording rate, message geometry and gesture class. Report actual samples, approximate fits and unverified assumptions separately. Do not compare raw pixel gaps from different devices or use the demo's16pt static gap as the Messages recording's static gap. The current code includes no fitted half-life assertion or automated claim of a perfect match.
