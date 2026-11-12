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

    private func makeCollection() -> (UICollectionView, MessageMotionLayout, Items) {
        let layout = MessageMotionLayout()
        let view = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), collectionViewLayout: layout)
        let data = Items()
        view.contentInsetAdjustmentBehavior = .never
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        view.dataSource = data
        layout.setItemHeights(Array(repeating: 120, count: 10), width: 390)
        view.reloadData()
        view.layoutIfNeeded()
        return (view, layout, data)
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
        XCTAssertEqual(first.center.y - 60, 6.63, accuracy: 0.001)
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
#endif
