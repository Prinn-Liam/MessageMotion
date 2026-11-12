// SPDX-License-Identifier: MIT
import Foundation
import CoreGraphics

enum MotionGeometry {
    static func displacement(delta: CGFloat, anchor: CGPoint, touch: CGPoint, strength: CGFloat) -> CGFloat {
        let weight = min(1, (abs(touch.y - anchor.y) + abs(touch.x - anchor.x)) / 1500)
        return delta * weight * strength
    }

    struct InputState {
        var dragging: Bool
        var coasting: Bool
        var decelerating: Bool
        var enabled: Bool
        var rebasing: Bool
        var sizeChanged: Bool
        var coastInjection: Bool

        func acceptsInput(proposedY: CGFloat, minimumY: CGFloat, maximumY: CGFloat) -> Bool {
            guard enabled, !rebasing, !sizeChanged else { return false }
            if dragging { return true }
            return coasting && decelerating && coastInjection && proposedY >= minimumY && proposedY <= maximumY
        }
    }

    static func projectMinimumGap(_ frames: [CGRect], anchor: Int, normalGap: CGFloat,
                                  minimumRatio: CGFloat) -> [CGRect] {
        guard frames.indices.contains(anchor), frames.count > 1 else { return frames }
        var frames = frames
        let paddingOverlap = normalGap * (min(1, max(0, minimumRatio)) - 1)
        for i in (anchor + 1)..<frames.count {
            frames[i].origin.y = max(frames[i].minY, frames[i - 1].maxY + paddingOverlap)
        }
        if anchor > 0 {
            for i in stride(from: anchor - 1, through: 0, by: -1) {
                frames[i].origin.y = min(frames[i].minY, frames[i + 1].minY - paddingOverlap - frames[i].height)
            }
        }
        return frames
    }

    static func rebasedOffset(offset: CGFloat, lag: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(maximum, max(minimum, offset - lag))
    }

    static func shouldFollow<ID: Equatable>(previousLatest: ID?, latest: ID?, nearBottom: Bool, outgoing: Bool) -> Bool {
        latest != nil && latest != previousLatest && (nearBottom || outgoing)
    }

    static func returnOffset(from: CGFloat, latest: CGFloat, progress: Double) -> CGFloat {
        let p = min(1, max(0, progress))
        return from + (latest - from) * CGFloat(1 - pow(1 - p, 3))
    }
}
