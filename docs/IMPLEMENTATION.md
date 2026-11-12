# Reproducing a Messages-inspired chat window

This is the English implementation contract for the standalone package. The [Chinese specification](IMPLEMENTATION.zh-Hans.md) was written before the implementation. Both describe public UIKit APIs and a user-approved prototype; neither claims access to Apple's internal implementation.

## Behavior to preserve

Slow dragging produces a small spacing response; fast scrolling produces a larger one. Momentum continues deforming bubbles while the page is moving, with decreasing input as scrolling slows. Initial touch stops native momentum promptly, while residual spacing settles. Minimum visible spacing remains bounded. Focus from history travels through intermediate messages to the latest row. Interactive or ordinary keyboard dismissal moves existing and newly visible rows together. Respect Reduce Motion and suspend bubble deformation while composing.

The original prototype's spring and keyboard behavior was accepted on a physical iPhone. Extraction introduces a new integration boundary and must be validated separately; original acceptance is not proof of exact new behavior on every device.

## Ownership and minimal architecture

- `MotionConfiguration`: normalized starting values, Codable for reproducible reports.
- `MotionGeometry`: actual runtime calculations for distance input, spacing projection, contact rebase, follow policy and return-scroll interpolation.
- `MessageMotionLayout`: resting row geometry, animated attributes, independent native attachments and gesture/coasting lifecycle.
- `MotionChat`: generic SwiftUI entry point; requires stable unique IDs and Equatable messages, with Sendable IDs. Bubble and composer builders remain caller-owned.
- `MotionTranscriptController`: UIKit collection view, diffable data source, cached SwiftUI row measurements, reading anchor and keyboard layout guide.
- `ReturnToLatestDriver`: cancellable display link with a weak target, avoiding a controller/display-link retain cycle.

Only Apple frameworks are used. The independent example owns synthetic messages and its visual style. There is no backend, persistent storage or dependency on the originating application. The public core intentionally omits superseded screen-field and nonlinear-damping experiments.

## Native spring input

Keep resting attributes separate from the attributes used as UIKit dynamic items. Create a `UIDynamicAnimator(collectionViewLayout:)`; give every loaded row a `UIAttachmentBehavior` with its anchor at that row's resting center and length0.

Starting preset:4.5Hz, damping1, strength0.65, normal gap16pt, minimum gap ratio0.6, momentum input enabled. The4.5Hz value is inferred from recording behavior, not an Apple-provided constant. UIKit's attachment API defines damping1 as critical damping.

For each eligible vertical bounds change:

```text
delta = proposedBounds.minY - currentBounds.minY
weight = min(1, (abs(anchor.y-touch.y) + abs(anchor.x-touch.x)) / 1500)
animated.center.y += delta * weight * strength
animator.updateItem(usingCurrentState: animated)
```

This perturbs native positions and lets UIKit restore them. It does not replace the physics solver with a hand-written envelope or multiply excitation by an extra gesture-speed gain. At the same frame cadence, scroll displacement increases with speed; the complete response also depends on native integration, spring coefficients, refresh rate and row geometry.

During direct dragging use the native pan location in content coordinates. Save its viewport position. During native deceleration, convert that saved position using the current bounds origin on every input step. Enable this input only when the proposed offset is inside the legal scroll range. Edge rubber-band return is not an additional excitation source. Programmatic scroll, touch rebase and keyboard size changes must not inject.

`beginDragging` clears coasting; `endDragging(willDecelerate:)` starts it only when native momentum will follow. End deceleration, initial touch and reset clear it. The original resting geometry never changes merely because a bubble is displaced.

## Minimum spacing and visibility

The measured row contains the bubble plus normal bottom padding, except on the last row. Thus visible gap equals `next.minY - previous.maxY + normalGap`.

Choose the animated row nearest the touch as the fixed projection anchor. Walk outward in both directions, moving only rows that violate the minimum gap. Minimum visible gap is `normalGap * clamp(minimumRatio, 0...1)`. The equivalent cell-frame gap is `normalGap * (minimumRatio-1)`. Keep the anchor fixed and do not resize bubbles. Apply projection to native items in a physics action and to attribute copies before rendering.

Return rows whose **animated/projected** frames intersect the requested rect. Selecting by resting positions first can omit a visibly displaced row and produce blank exposure. This implementation keeps states for all loaded rows while cells remain reusable. Its O(n) state and queries require a bounded loaded history; large-scale windowing is a separate design.

## Touch interruption and continued settling

Observe initial contact without consuming the native pan: no delay, no cancellation of child touches, and return false from the observer's `shouldReceive`.

1. Stop native momentum with `stopScrollingAndZooming()` (iOS17.4+, with UIKit's documented boundary exceptions).
2. Find the visible animated row nearest the touch and compute its offset from the resting row.
3. Request `contentOffset.y - lag`, clamped to legal bounds.
4. Add the **actual** offset correction to all animated centers, and change contentOffset in the same nonanimated transaction. Every screen coordinate `center-offset` stays continuous.
5. Recreate independent native attachments at resting anchors. The touched row becomes a resting reference when compensation is not clamped; surrounding gaps settle.

This adopted path clears prior native velocities at contact. Preserving velocity by replacing the mechanism would be a behavioral change, not cleanup. Exact pinning cannot be promised when a content boundary limits compensation. No separate near-to-far recovery wave is implemented.

## Keyboard geometry and real scrolling

Constrain composer.bottom to `keyboardLayoutGuide.top`; constrain the collection view bottom to composer.top. Set interactive keyboard dismissal and keyboardDismissPadding equal to composer height. Only this component ignores SwiftUI keyboard avoidance, giving UIKit one geometry owner.

Track whether the reader follows latest, is reading history, is dragging, or is returning to latest. Follow a newly sent outgoing message; for incoming messages follow only when already near the bottom. Use stable IDs and resting-frame coordinates to preserve history anchors during updates. Cache row measurements by message value, width, last-row status, normal gap, Dynamic Type and external layoutRevision.

When focus needs to return from history, animate viewport layout with the native keyboard duration/curve. Do **not** animate contentOffset in that UIView animation block. A separate display link updates real offsets so intermediate rows are actually laid out:

```text
p = clamp((targetTimestamp-startTime)/0.35, 0...1)
offset = initialOffset + (latestOffsetNow-initialOffset) * (1-(1-p)^3)
```

Reread latestOffset each frame because the keyboard is resizing the viewport. For travel exceeding six viewports, first jump without animation to the final six; this is an intentional travel cap. Touch, a new drag and teardown cancel the driver. Enable follow-latest only after completion. With reduced motion, position directly.

Row geometry depends on width, not viewport height. Return true for a meaningful **width** change, not keyboard height changes. Height invalidation inside a keyboard animation can start collection-view bounds transitions, giving entering rows independent fades and motion. Appearing/disappearing attributes retain their own position and opacity; complete new-cell layout without animation and strip initial layer animations in `willDisplay`. Custom bubble content that owns layer animations needs separate integration testing.

## Verification and observations

Core tests exercise normalized configuration, distance/direction/cap, direct/coast/boundary gating, randomized spacing constraints, contact coordinate continuity, follow policy and cubic retargeting. Native tests exercise real collection layout input/culling, height-only invalidation, contact compensation, opaque entering rows, return-scroll cancellation/completion and display-link lifetime.

Runtime verification includes history → focus → latest with a software keyboard, ordinary and interactive dismissal, quick drag/catch, incoming/outgoing updates, empty history, long history and reduced motion. Record exactly which paths were observed. A successful geometry test is not a measurement of Messages-equivalent feel. See [VALIDATION](VALIDATION.md).

Reference observations from one original recording analysis: slow-drag spacing roughly±5pt, fast-scroll compression−13pt/expansion+19...29pt, contact settling about0.17s, compression floor about0.62 of resting gap. Recordings had different static gap sizes and bubble heights. These are observations of those recordings, not universal assertions for arbitrary UI styles. The fitted preset and the user-accepted original implementation remain separate evidence from post-extraction video comparison.

## Related public work

[objc.io's collection-view dynamics article](https://www.objc.io/issues/5-ios7/collection-views-and-uidynamics/) explains independent native attachments. [BouncyLayout](https://github.com/roberthein/BouncyLayout) is an existing related open-source implementation. Apple's [stopScrollingAndZooming documentation](https://developer.apple.com/documentation/uikit/uiscrollview/stopscrollingandzooming()) describes momentum interruption and edge exceptions. No external implementation is a bundled dependency; attribution is in [NOTICE](../NOTICE.md).
