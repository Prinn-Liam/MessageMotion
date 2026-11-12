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

`docs/media/scroll.gif` and `docs/media/keyboard.gif` were recorded from MessageMotionDemo, iPhone 18 Pro Simulator, iOS 27.2, on 2026-11-11. Both use in-memory sample messages and normal-speed source timing. They are not Apple Messages recordings and contain no production account or private business data.

- Scrolling: drag and spring-spacing recovery; this clip does not separately measure fast-touch interruption latency.
- Keyboard: focus from history, return to latest, then use the example's keyboard-dismiss button. This clip does not demonstrate interactive finger-following dismissal.

GIFs are 360×782, 25 fps, infinitely looped. Edits are trim, timestamp normalization, scaling, frame-rate conversion and palette compression. No speed multiplier, synthetic bubble motion, frame interpolation or replacement UI was used. Source hashes and trim intervals are in `docs/media/provenance.json`; raw recordings are not distributed.

`Tools/make_showcase_media.py` encodes reviewed raw captures using optional maintainer tool ffmpeg. Intermediate MP4s are temporary; only GIFs and provenance are distributed. Update its trim intervals for different source takes. The existing GIF bytes were preserved when removing the website.

## Scope and checks

This is a public-API approximation of scrolling behavior, not Apple's internal implementation or all Messages effects. See [implementation](IMPLEMENTATION.md), [validation](VALIDATION.md) and [NOTICE](../NOTICE.md).

The independent website and its build helper were archived outside the portable package at the owner's request. Local README links, media paths, source preservation and the exported archive were checked. Current remote test results are available in [GitHub Actions](https://github.com/Prinn-Liam/MessageMotion/actions); the presence of a workflow file alone is not evidence of a successful run.
