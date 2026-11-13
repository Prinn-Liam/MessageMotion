// SPDX-License-Identifier: MIT
import Foundation

/// The measured starting preset. These are fitted values, not Apple's private constants.
public struct MotionConfiguration: Equatable, Codable, Sendable {
    public var frequency: Double
    public var damping: Double
    public var dragStrength: Double
    public var minimumGapRatio: Double
    public var normalGap: Double
    public var deformsDuringDeceleration: Bool

    public init(frequency: Double = 4.5, damping: Double = 0.7, dragStrength: Double = 1.5,
                minimumGapRatio: Double = 0.6, normalGap: Double = 16,
                deformsDuringDeceleration: Bool = true) {
        self.frequency = frequency
        self.damping = damping
        self.dragStrength = dragStrength
        self.minimumGapRatio = minimumGapRatio
        self.normalGap = normalGap
        self.deformsDuringDeceleration = deformsDuringDeceleration
    }

    public static let messagesLike = Self()

    /// Normalizes external configuration before it reaches UIKit's physics engine.
    public var normalized: Self {
        func bound(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        return Self(frequency: bound(frequency, 0.4...8, 4.5),
                    damping: bound(damping, 0.2...1, 0.7),
                    dragStrength: bound(dragStrength, 0...2.5, 1.5),
                    minimumGapRatio: bound(minimumGapRatio, 0...1, 0.6),
                    normalGap: bound(normalGap, 0...64, 16),
                    deformsDuringDeceleration: deformsDuringDeceleration)
    }

    private enum CodingKeys: String, CodingKey {
        case frequency, damping, dragStrength, minimumGapRatio, normalGap, deformsDuringDeceleration
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(frequency: try values.decodeIfPresent(Double.self, forKey: .frequency) ?? 4.5,
                  damping: try values.decodeIfPresent(Double.self, forKey: .damping) ?? 0.7,
                  dragStrength: try values.decodeIfPresent(Double.self, forKey: .dragStrength) ?? 1.5,
                  minimumGapRatio: try values.decodeIfPresent(Double.self, forKey: .minimumGapRatio) ?? 0.6,
                  normalGap: try values.decodeIfPresent(Double.self, forKey: .normalGap) ?? 16,
                  deformsDuringDeceleration: try values.decodeIfPresent(Bool.self, forKey: .deformsDuringDeceleration) ?? true)
    }
}
