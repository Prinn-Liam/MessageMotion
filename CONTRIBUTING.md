# Contributing

Keep changes focused on motion and chat geometry. Provide the device/iOS version, refresh rate where known, configuration JSON, and the gesture or keyboard sequence needed to reproduce an issue. Use synthetic messages; do not attach personal conversations or recordings without removing private content.

Run `swift test` for the core and the example scheme's iOS tests for native behavior. For changes to scrolling, culling or keyboard ownership, include a Simulator or iPhone reproduction. Measurements should distinguish observations from inferred spring parameters, use points rather than unlabelled pixels, and record frame rate and display scale.

Preserve accessibility reduce-motion handling and avoid adding a second keyboard-avoidance owner. Do not add networking, persistence or third-party runtime dependencies to demonstrate an animation.

The checked-in Xcode project runs without generators. If changing its source list, `xcodegen generate --spec Example/project.yml` regenerates it using XcodeGen; retain the relative local-package path and leave development-team settings out.
