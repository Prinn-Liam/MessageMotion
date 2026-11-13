# Validation record

## 2026-11-12: slow-drag refinement and preset update

The current layout keeps continuous `UIDynamicItem` state separate from display attributes and uses nonzero-length native attachments. Defaults are frequency 4.5 Hz, damping 0.7, drag strength 1.5, minimum gap ratio 0.6, normal gap 16 pt and deceleration deformation enabled. No input threshold or custom spring solver was added.

Focused checks on the public checkout (Xcode 27.2, iPhone 18 Pro Max Simulator, iOS 27.2):

- macOS core: 8 tests passed, including default/partial-JSON/nonfinite-value consistency.
- Native layout: 6 tests passed. Covers steady subpixel input in both directions and natural settling, large-input minimum gaps, displayed-cell positions, animated visibility, touch continuity, height changes and Reduce Motion.
- The subpixel test samples native display frames and requires at least 60 uninterrupted steady samples after warmup; missed frames restart warmup rather than being treated as continuous input. This is test synchronization, not runtime filtering.
- Portable source export and whitespace checks passed. No full application suite or new visual interaction run was performed for this publication.

The owner previously tested the refined demo on a physical iPhone and reported improved slow dragging, then selected the current parameters. That observation is distinct from the automated public-checkout checks above. The existing demo videos predate this update and do not demonstrate the new tuning. The original extraction evidence below is historical.

## Original extraction (2026-11-11)

Date:2026-11-11. Local toolchain: Xcode27.2 (27B52), Swift6.4.2. Example minimum deployment: iOS18. Simulator: iPhone18Pro, iOS27.2. This records the independent extraction, not every device supported by the deployment target.

## Automated checks completed

- Core suite on macOS:8 tests,0 failures. Configuration normalization/migration, distance input, coast/boundary gate, randomized floor projection (400 generated transcripts), touch coordinate rebase, follow policy and return interpolation.
- Full native suite on iOS Simulator:14 tests,0 failures,0 skipped. Includes the core plus height-only invalidation, actual collection-layout input and animated culling, native touch rebase, reduced-motion resting attributes, opaque arriving rows, return cancellation/completion and weak display-link ownership.
- Measurement helper:4 Python standard-library tests,0 failures. Segmentation, track translation, point/speed units and partial-row exclusion. An additional lossless synthetic-video end-to-end run processed60 frames with0pt gap-deviation error and the expected−60pt/s median translation. These do not validate arbitrary real recordings.
- Simulator Debug build/run succeeded without compiler warnings/errors for the standalone example.

Core tests were written before the implementation and failed with missing symbols, then passed. Measurement tests likewise failed before the tool existed. Native integration assertions use actual UIKit layout objects and the return-scroll driver, not a substitute spring solver.

## Interactions observed

The independent app starts at message40. A real native multi-step drag moved into history (messages28–34). Focusing the composer returned to message40. The simulator initially used a hardware keyboard; after toggling its software keyboard, the composer moved above it and the last message remained visible. Dismissing with the app's keyboard button returned to the full-height list with message40 at the bottom.

An empty-history launch and the first incoming message were also observed; a400-message launch with the reduce-motion override displayed the last message correctly.

These observations establish the exercised path and settled geometry. They are not a frame-by-frame analysis of keyboard transitions or a matched Messages motion measurement. One automation action completed its drag but timed out while waiting for the refreshed semantic snapshot; the actual history position was independently observed afterward.

## Delivery checks

The source archive was extracted to a fresh directory outside the originating project and independently built for iOS Simulator with signing disabled. Its SHA256 manifest and absence of caches/signing files were checked. A separately identified iPhone build and strict signature/profile/device-inclusion checks succeeded. Physical installation was refused because the test phone already had three free-provisioned apps; the user chose to host the exact demo views/package inside the existing sandbox while retaining the original chat for comparison. That host integration is separate from the self-contained public example. The existing sandbox was updated in place and launched directly into the new demo without diagnostic capture. The original chat entry remains available. The user then compared fast scroll, touch stop, history→focus and keyboard dismissal on the physical phone and explicitly confirmed: “和原版一致” (consistent with the original). No installed app was removed, and production/customer app metadata remained unchanged.

Remote runs are listed in [GitHub Actions](https://github.com/Prinn-Liam/MessageMotion/actions). Check a completed run for the commit you are using; a workflow file alone is not evidence of a passing run.

## Reference and remaining limits

The originating prototype's bubble motion and keyboard fixes were explicitly approved on a physical iPhone. This extraction retains its spring coefficients, distance excitation, momentum reference, compression floor, touch rebase and keyboard ownership while removing superseded experiments and business dependencies. The weak return-scroll target and cache revision are local organization/lifetime improvements.

No post-extraction matched recordings of Messages and this demo have yet been analyzed. The user accepted physical parity with the original prototype. Pixel-perfect equivalence to Messages, identical behavior on all refresh rates, and a separate near-to-far recovery wave are not claimed. Touch catch clears native spring velocities; edge-clamped compensation is an exception to strict touch pinning. Large unbounded histories and custom animated bubble content need their own integration work.
