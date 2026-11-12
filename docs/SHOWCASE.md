# GitHub README and demo notes

The repository README is the project introduction. It describes a SwiftUI component for Apple Messages / iMessage-style bubble scrolling and keyboard coordination. No standalone website is included.

Repository: [Prinn-Liam/MessageMotion](https://github.com/Prinn-Liam/MessageMotion).

## GitHub About

> Apple Messages / iMessage-style bubble scrolling for SwiftUI. Native springs, touch interruption, minimum spacing and keyboard-aware scrolling. Swift Package + iPhone example.

Topics:

```text
swift swiftui ios uikit swift-package chat-ui imessage apple-messages
scroll-animation spring-animation uidynamics uicollectionview keyboard
```

The first README paragraph states the use case; tables identify requirements and entry points; the API names and implementation links let an agent inspect the code. The root llms.txt is an optional short index, not a guarantee of crawler discovery or search ranking. The public repository uses this description and topic set.

## Demo provenance

The current demos come from a physical iPhone screen recording supplied by the project owner on 2026-11-11. It shows the MessageMotion example views hosted in the local sandbox, using in-memory sample messages. It is not Apple Messages footage. No production conversations, original audio or source recording metadata are distributed.

The source presents 433 decoded frames over approximately 7.2167 seconds. Frame timestamps are consistently about 16.7 ms apart, with no interval above 50 ms. The header's stored frame count differs from the decoded presentation count because of container/edit-list metadata; use decoded timestamps when evaluating pacing. This replaces the earlier Simulator capture that contained long frame gaps during motion.

- `docs/media/demo.mp4`: the complete sequence at 1× speed, H.264, 660×1274, 60 fps, silent, fast-start. It includes the initial history movement, composer focus/return to latest, keyboard dismissal with synchronized list adjustment, and repeated quick flicks/touch stops.
- `docs/media/keyboard.gif`: source interval 1.35–3.10 seconds, covering keyboard coordination and latest-message positioning.
- `docs/media/scroll.gif`: source interval 3.10–7.216667 seconds, covering repeated quick flicks and touch stops.

GIFs are 320×618 at 50 fps and loop. GIF playback is a preview; use the full MP4 or the app to inspect finer motion. Clip endpoints can differ by one frame due to timing quantization. No playback-speed change, optical-flow interpolation, synthetic bubble motion or replacement UI was used.

Only the top 320 source pixels were cropped: system status and host back-navigation UI. The component header, transcript, composer and keyboard remain visible. Source dimensions, hash, crop and clip intervals are in `docs/media/provenance.json`; the original MOV remains local and unchanged.

Re-encode the reviewed capture with optional maintainer tools ffmpeg/ffprobe:

```sh
python3 Tools/make_showcase_media.py --source /path/to/reviewed-iphone-recording.MOV
```

This is an edit recipe for this specific 1320×2868 capture. Review its crop and intervals before using a different recording. It strips audio and recording metadata, writes the full MP4 and two GIFs, and updates provenance. The source archive includes only these intentionally public assets, not arbitrary MOV/MP4 files.

## Scope and checks

This is a public-API approximation of scrolling behavior, not Apple's internal implementation or all Messages effects. See [implementation](IMPLEMENTATION.md), [validation](VALIDATION.md) and [NOTICE](../NOTICE.md).

The independent website and its build helper were archived outside the portable package at the owner's request. Local README links, media paths, source preservation and the exported archive were checked. Current remote test results are available in [GitHub Actions](https://github.com/Prinn-Liam/MessageMotion/actions); the presence of a workflow file alone is not evidence of a successful run.
