#if canImport(UIKit)
import UIKit
import XCTest
@testable import MessageMotion

@MainActor
final class NativeLayoutTests: XCTestCase {
    private final class Items: NSObject, UICollectionViewDataSource {
        var count = 10
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
    }

    private func makeCollection(count: Int = 10) -> (UICollectionView, MessageMotionLayout, Items) {
        let layout = MessageMotionLayout()
        let view = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), collectionViewLayout: layout)
        let data = Items()
        data.count = count
        view.contentInsetAdjustmentBehavior = .never
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        view.dataSource = data
        layout.setItemHeights(Array(repeating: 120, count: count), width: 390)
        view.reloadData()
        view.layoutIfNeeded()
        return (view, layout, data)
    }

    func testSubpixelInputSurvivesNativeStepsWithoutBackAndForthDrift() async throws {
        for direction: CGFloat in [-1, 1] {
            let (view, layout, items) = makeCollection(count: 40)
            defer { layout.reset(); withExtendedLifetime(items) {} }
            // Match the demo probe: row 5 sits near the current touch, so this
            // exercises the small distance-weighted input that exposed drift.
            view.contentOffset.y = 600
            layout.beginDragging()
            let path = IndexPath(item: 5, section: 0)
            let rest = try XCTUnwrap(layout.restingFrame(at: path)).midY
            var samples: [CGFloat] = []
            let clock = MotionTestFrameClock()
            defer { clock.stop() }
            // Drive and sample on display frames. A 17ms wall-clock timer beats
            // against native animation and introduces an artificial periodic gap.
            var consecutiveFrames = 0
            var previousSampleTime = CACurrentMediaTime()
            for _ in 0..<150 {
                var proposed = view.bounds
                proposed.origin.y += 0.15 * direction
                _ = layout.shouldInvalidateLayout(forBoundsChange: proposed)
                let scheduledInterval = await clock.next()
                let now = CACurrentMediaTime()
                let interval = max(scheduledInterval, now - previousSampleTime)
                previousSampleTime = now
                // A missed display frame interrupts the input; the native spring
                // correctly settles during that gap. Warm up again before
                // asserting the separate steady-input contract.
                consecutiveFrames = interval <= 1.5 / 60 ? consecutiveFrames + 1 : 0
                if consecutiveFrames >= 30 {
                    samples.append((try XCTUnwrap(layout.layoutAttributesForItem(at: path)).center.y - rest) * direction)
                }
            }
            XCTAssertGreaterThanOrEqual(samples.count, 60, "The run must contain enough uninterrupted steady input")
            XCTAssertGreaterThan(samples.min() ?? 0, 0.01,
                "A same-direction subpixel input must survive native steps; no rounding away or reversal: \(samples)")
            XCTAssertLessThan((samples.max() ?? 0) - (samples.min() ?? 0), 0.1,
                "Steady small input must not cycle around the resting point: \(samples)")
            layout.endDragging(willDecelerate: false)
            try await Task.sleep(for: .milliseconds(900))
            XCTAssertEqual(try XCTUnwrap(layout.layoutAttributesForItem(at: path)).center.y, rest, accuracy: 0.01)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(try XCTUnwrap(layout.layoutAttributesForItem(at: path)).center.y, rest, accuracy: 0.01)
        }
    }

    func testLargeInputKeepsGapCullingAndTouchCatch() async throws {
        let (view, layout, items) = makeCollection()
        defer { layout.reset(); withExtendedLifetime(items) {} }
        let window = UIWindow(frame: view.frame)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.layoutIfNeeded()
        layout.beginDragging()
        for delta: CGFloat in [120, 240, -480, -120, 900, -900] {
            var proposed = view.bounds
            proposed.origin.y += delta
            _ = layout.shouldInvalidateLayout(forBoundsChange: proposed)
            try await Task.sleep(for: .milliseconds(20))
            let attributes = try XCTUnwrap(layout.layoutAttributesForElements(in:
                CGRect(x: 0, y: -10000, width: 390, height: 30000)))
                .sorted { $0.indexPath.item < $1.indexPath.item }
            XCTAssertEqual(attributes.count, 10)
            view.layoutIfNeeded()
            XCTAssertFalse(view.visibleCells.isEmpty)
            for cell in view.visibleCells {
                let path = try XCTUnwrap(view.indexPath(for: cell))
                let expected = try XCTUnwrap(layout.layoutAttributesForItem(at: path))
                XCTAssertEqual(cell.frame.minY, expected.frame.minY, accuracy: 0.5,
                    "The collection must render the native solver's updated positions")
            }
            for (a, b) in zip(attributes, attributes.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.frame.minY - a.frame.maxY + 16, 9.6 - 0.001)
            }
        }
        let before = Dictionary(uniqueKeysWithValues: try XCTUnwrap(layout.layoutAttributesForElements(in: view.bounds)).map {
            ($0.indexPath, $0.center.y - view.contentOffset.y)
        })
        layout.interruptOnTouchDown(at: CGPoint(x: 195, y: view.bounds.midY))
        for (path, y) in before {
            XCTAssertEqual(try XCTUnwrap(layout.layoutAttributesForItem(at: path)).center.y - view.contentOffset.y,
                y, accuracy: 0.5)
        }
        layout.endDragging(willDecelerate: false)
        try await Task.sleep(for: .milliseconds(1200))
        for index in 0..<10 {
            let path = IndexPath(item: index, section: 0)
            XCTAssertEqual(try XCTUnwrap(layout.layoutAttributesForItem(at: path)).center.y,
                try XCTUnwrap(layout.restingFrame(at: path)).midY, accuracy: 0.01)
        }
        layout.enabled = false
        layout.beginDragging()
        var proposed = view.bounds
        proposed.origin.y += 120
        _ = layout.shouldInvalidateLayout(forBoundsChange: proposed)
        let path = IndexPath(item: 8, section: 0)
        XCTAssertEqual(layout.layoutAttributesForItem(at: path)?.frame, layout.restingFrame(at: path))
    }

    func testHeightOnlyChangeDoesNotStartAnimatedBoundsTransition() {
        let (view, layout, data) = makeCollection()
        defer { withExtendedLifetime(data) {} }
        var bounds = view.bounds
        bounds.size.height = 350
        XCTAssertFalse(layout.shouldInvalidateLayout(forBoundsChange: bounds))
        bounds.size.width = 420
        XCTAssertTrue(layout.shouldInvalidateLayout(forBoundsChange: bounds))
    }

    func testNativeInputAndAnimatedFrameCulling() {
        let (view, layout, data) = makeCollection()
        defer { withExtendedLifetime(data) {} }
        layout.beginDragging()
        var proposed = view.bounds
        proposed.origin.y += 60
        _ = layout.shouldInvalidateLayout(forBoundsChange: proposed)
        let first = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!
        XCTAssertEqual(first.center.y - 60, 15.3, accuracy: 0.001)
        let crossing = layout.layoutAttributesForElements(in: CGRect(x: 0, y: 490, width: 390, height: 4))!
        XCTAssertTrue(crossing.contains { $0.indexPath.item == 3 }, "An animated row entering from outside its resting rect must be available")
        layout.endDragging(willDecelerate: false)
    }

    func testTouchRebaseKeepsScreenCoordinatesContinuous() {
        let (view, layout, data) = makeCollection()
        defer { withExtendedLifetime(data) {} }
        view.contentOffset.y = 200
        layout.beginDragging()
        var proposed = view.bounds
        proposed.origin.y += 60
        _ = layout.shouldInvalidateLayout(forBoundsChange: proposed)
        let before = Dictionary(uniqueKeysWithValues: layout.layoutAttributesForElements(in: view.bounds)!.map {
            ($0.indexPath, $0.center.y - view.contentOffset.y)
        })
        layout.interruptOnTouchDown(at: CGPoint(x: 195, y: 350))
        for (path, y) in before {
            let after = layout.layoutAttributesForItem(at: path)!.center.y - view.contentOffset.y
            XCTAssertEqual(after, y, accuracy: 0.5)
        }
    }

    func testReduceMotionUsesRestingGeometryAndOpaqueAppearingRows() {
        let (view, layout, data) = makeCollection()
        defer { withExtendedLifetime(data) {} }
        layout.enabled = false
        layout.beginDragging()
        var proposed = view.bounds
        proposed.origin.y += 100
        _ = layout.shouldInvalidateLayout(forBoundsChange: proposed)
        let item = IndexPath(item: 2, section: 0)
        XCTAssertEqual(layout.layoutAttributesForItem(at: item)!.frame.minY, 240)
        XCTAssertEqual(layout.initialLayoutAttributesForAppearingItem(at: item)?.alpha, 1)
        XCTAssertEqual(layout.finalLayoutAttributesForDisappearingItem(at: item)?.alpha, 1)
    }
}
@MainActor
private final class MotionTestFrameClock: NSObject {
    private var link: CADisplayLink?
    private var pending: CheckedContinuation<TimeInterval, Never>?
    private var lastTimestamp: CFTimeInterval?
    override init() {
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    func next() async -> TimeInterval { await withCheckedContinuation { pending = $0 } }
    @objc private func frame() {
        guard let link else { return }
        let interval = lastTimestamp.map { link.timestamp - $0 } ?? link.targetTimestamp - link.timestamp
        lastTimestamp = link.timestamp
        let continuation = pending
        pending = nil
        continuation?.resume(returning: interval)
    }
    func stop() { link?.invalidate(); link = nil }
}

#endif
