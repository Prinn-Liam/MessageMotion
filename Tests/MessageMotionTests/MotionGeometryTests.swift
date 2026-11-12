import XCTest
import CoreGraphics
@testable import MessageMotion

final class MotionGeometryTests: XCTestCase {
    func testDistanceWeightedInputKeepsDirectionAndCapsResistance() {
        let anchor = CGPoint(x: 200, y: 500)
        XCTAssertEqual(MotionGeometry.displacement(delta: 30, anchor: anchor, touch: CGPoint(x: 200, y: 200), strength: 0.65), 3.9, accuracy: 0.000001)
        XCTAssertEqual(MotionGeometry.displacement(delta: -30, anchor: anchor, touch: CGPoint(x: 200, y: 200), strength: 0.65), -3.9, accuracy: 0.000001)
        XCTAssertEqual(MotionGeometry.displacement(delta: 30, anchor: anchor, touch: CGPoint(x: 200, y: -5000), strength: 0.65), 19.5, accuracy: 0.000001)
    }

    func testCoastingDeformsOnlyInsideContentAndNeverDuringRebaseOrResize() {
        let state = MotionGeometry.InputState(dragging: false, coasting: true, decelerating: true,
            enabled: true, rebasing: false, sizeChanged: false, coastInjection: true)
        XCTAssertTrue(state.acceptsInput(proposedY: 40, minimumY: -16, maximumY: 400))
        XCTAssertFalse(state.acceptsInput(proposedY: -17, minimumY: -16, maximumY: 400))
        XCTAssertFalse(state.acceptsInput(proposedY: 401, minimumY: -16, maximumY: 400))
        var disabled = state
        disabled.coastInjection = false
        XCTAssertFalse(disabled.acceptsInput(proposedY: 40, minimumY: -16, maximumY: 400))
        disabled.dragging = true
        XCTAssertTrue(disabled.acceptsInput(proposedY: -30, minimumY: -16, maximumY: 400))
        disabled.rebasing = true
        XCTAssertFalse(disabled.acceptsInput(proposedY: 40, minimumY: -16, maximumY: 400))
        disabled.rebasing = false
        disabled.sizeChanged = true
        XCTAssertFalse(disabled.acceptsInput(proposedY: 40, minimumY: -16, maximumY: 400))
    }

    func testProjectionKeepsAnchorAndEnforcesVisibleEdgeFloor() {
        let frames = [CGRect(x: 0, y: 0, width: 400, height: 96),
                      CGRect(x: 0, y: 70, width: 400, height: 76),
                      CGRect(x: 0, y: 120, width: 400, height: 116)]
        let result = MotionGeometry.projectMinimumGap(frames, anchor: 1, normalGap: 16, minimumRatio: 0.6)
        XCTAssertEqual(result[1], frames[1])
        XCTAssertEqual(result[0].minY, -19.6, accuracy: 0.000001)
        XCTAssertEqual(result[2].minY, 139.6, accuracy: 0.000001)
        for (a, b) in zip(result, result.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.minY - a.maxY + 16, 9.6 - 0.000001)
        }
        XCTAssertEqual(MotionGeometry.projectMinimumGap(result, anchor: 1, normalGap: 16, minimumRatio: 0.6), result)
    }

    func testRandomizedProjectionPreservesAnchorAndFloorAcrossEveryRatio() {
        var seed: UInt64 = 530
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1
            return Double(seed >> 11) / Double(UInt64.max >> 11)
        }
        for ratio in [0.0, 0.2, 0.6, 1.0] {
            for _ in 0..<100 {
                var y = 0.0
                let frames = (0..<40).map { _ -> CGRect in
                    let height = 50 + random() * 100
                    defer { y += height }
                    return CGRect(x: 0, y: y + random() * 600 - 300, width: 390, height: height)
                }
                let anchor = Int(random() * 39)
                let projected = MotionGeometry.projectMinimumGap(frames, anchor: anchor, normalGap: 16, minimumRatio: ratio)
                XCTAssertEqual(projected[anchor], frames[anchor])
                for (a, b) in zip(projected, projected.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(b.minY - a.maxY + 16, 16 * ratio - 0.000001)
                }
            }
        }
    }

    func testTouchRebasePreservesEveryScreenPositionIncludingClampedBoundary() {
        for offset in [10.0, 500, 995] {
            let target = MotionGeometry.rebasedOffset(offset: offset, lag: 40, minimum: 0, maximum: 1000)
            let correction = target - offset
            for center in [70.0, 700, 1300] {
                XCTAssertEqual(center + correction - target, center - offset, accuracy: 0.000001)
            }
        }
        XCTAssertEqual(MotionGeometry.rebasedOffset(offset: 500, lag: 40, minimum: 0, maximum: 1000), 460)
    }

    func testConfigurationNormalizesInvalidValuesAndPartialJSONUsesCurrentDefaults() throws {
        let decoded = try JSONDecoder().decode(MotionConfiguration.self, from: Data("{\"minimumGapRatio\":0.8}".utf8))
        XCTAssertEqual(decoded.minimumGapRatio, 0.8)
        XCTAssertEqual(decoded.frequency, 4.5)
        XCTAssertTrue(decoded.deformsDuringDeceleration)
        var bad = MotionConfiguration()
        bad.frequency = .nan
        bad.minimumGapRatio = -4
        bad.normalGap = .infinity
        bad.dragStrength = 100
        let safe = bad.normalized
        XCTAssertEqual(safe.frequency, 4.5)
        XCTAssertEqual(safe.minimumGapRatio, 0)
        XCTAssertEqual(safe.normalGap, 16)
        XCTAssertEqual(safe.dragStrength, 2.5)
        XCTAssertEqual(try JSONDecoder().decode(MotionConfiguration.self, from: JSONEncoder().encode(safe)), safe)
    }

    func testFollowPolicyProtectsHistoryAndFollowsOwnNewMessage() {
        XCTAssertFalse(MotionGeometry.shouldFollow(previousLatest: 2, latest: 2, nearBottom: true, outgoing: true))
        XCTAssertFalse(MotionGeometry.shouldFollow(previousLatest: 2, latest: 3, nearBottom: false, outgoing: false))
        XCTAssertTrue(MotionGeometry.shouldFollow(previousLatest: 2, latest: 3, nearBottom: true, outgoing: false))
        XCTAssertTrue(MotionGeometry.shouldFollow(previousLatest: 2, latest: 3, nearBottom: false, outgoing: true))
    }

    func testReturnScrollRetargetsAndEndsAtExactLatestPosition() {
        XCTAssertEqual(MotionGeometry.returnOffset(from: 0, latest: 800, progress: 0.5), 700, accuracy: 0.000001)
        XCTAssertEqual(MotionGeometry.returnOffset(from: 0, latest: 1000, progress: 0.5), 875, accuracy: 0.000001)
        XCTAssertEqual(MotionGeometry.returnOffset(from: 30, latest: 1000, progress: 2), 1000)
        XCTAssertEqual(MotionGeometry.returnOffset(from: 30, latest: 1000, progress: -1), 30)
    }
}
