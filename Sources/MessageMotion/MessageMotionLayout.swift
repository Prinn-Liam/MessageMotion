// SPDX-License-Identifier: MIT
#if canImport(UIKit)
import UIKit

/// Independent UIKit attachment springs, with resting geometry kept separate.
/// UIKit users must forward drag, deceleration, and initial-touch lifecycle events.
@MainActor
public final class MessageMotionLayout: UICollectionViewLayout, UIDynamicAnimatorDelegate {
    public var configuration = MotionConfiguration.messagesLike {
        didSet {
            updateSpringSettings()
            constrainMinimumGap(updateAnimator: true)
            invalidateLayout()
        }
    }
    public var enabled = true {
        didSet { if enabled != oldValue { reset() } }
    }

    // Layout attributes are pixel-quantized when UIKit Dynamics writes them.
    // Keep the native solver's subpixel state in an ordinary dynamic item, and
    // create layout attributes only for display (never feed them back as input).
    private final class SpringItem: NSObject, UIDynamicItem {
        var center: CGPoint
        let restingCenter: CGPoint
        let bounds: CGRect
        var transform = CGAffineTransform.identity
        init(frame: CGRect) {
            center = CGPoint(x: frame.midX, y: frame.midY)
            restingCenter = center
            bounds = CGRect(origin: .zero, size: frame.size)
        }
        var frame: CGRect {
            get { CGRect(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2,
                         width: bounds.width, height: bounds.height) }
            set { center = CGPoint(x: newValue.midX, y: newValue.midY) }
        }
    }
    private struct Spring {
        let item: SpringItem
        let attachment: UIAttachmentBehavior
    }
    private var resting: [UICollectionViewLayoutAttributes] = []
    private var springs: [Spring] = []
    private var heights: [CGFloat] = []
    private var width: CGFloat = 0
    private var height: CGFloat = 0
    private var dragging = false
    private var coasting = false
    private var rebasing = false
    private var touch = CGPoint.zero
    private var releaseTouchOnScreen = CGPoint.zero
    private lazy var animator = makeAnimator()
    private func makeAnimator() -> UIDynamicAnimator {
        let result = UIDynamicAnimator()
        result.delegate = self
        return result
    }

    /// Heights include normalGap bottom padding, except for the last message.
    public func setItemHeights(_ values: [CGFloat], width: CGFloat) {
        let values = values.map { $0.isFinite ? max(1, $0) : 1 }
        guard values != heights || abs(width - self.width) > 0.25 else { return }
        reset()
        heights = values
        self.width = width
        var y: CGFloat = 0
        resting = values.enumerated().map { index, value in
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            attributes.frame = CGRect(x: 0, y: y, width: width, height: value)
            y += value
            return attributes
        }
        height = y
        invalidateLayout()
    }

    public func restingFrame(at indexPath: IndexPath) -> CGRect? {
        resting.indices.contains(indexPath.item) ? resting[indexPath.item].frame : nil
    }

    public override var collectionViewContentSize: CGSize { CGSize(width: width, height: height) }

    public override func prepare() {
        super.prepare()
        guard enabled, let collectionView, collectionView.numberOfSections > 0 else { return }
        let count = min(resting.count, collectionView.numberOfItems(inSection: 0))
        if springs.count > count {
            for spring in springs[count...] { animator.removeBehavior(spring.attachment) }
            springs.removeLast(springs.count - count)
        }
        for index in springs.count..<count {
            let item = SpringItem(frame: resting[index].frame)
            let attachment = makeAttachment(item, anchor: resting[index].center)
            springs.append(Spring(item: item, attachment: attachment))
            animator.addBehavior(attachment)
        }
        installAction()
        updateSpringSettings()
    }

    private func makeAttachment(_ item: SpringItem, anchor: CGPoint) -> UIAttachmentBehavior {
        let settings = configuration.normalized
        // A zero-length attachment loses its restoring direction near its anchor.
        // Put the anchor above the reachable transcript instead: vertical extension
        // still equals the bubble's displacement, with the same frequency/damping.
        let length = max(height, collectionView?.bounds.height ?? 0, 1) * 4
        let attachment = UIAttachmentBehavior(item: item,
            attachedToAnchor: CGPoint(x: anchor.x, y: anchor.y - length))
        attachment.length = length
        attachment.frequency = CGFloat(settings.frequency)
        attachment.damping = CGFloat(settings.damping)
        return attachment
    }

    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        (enabled ? displayedAttributes() : resting).filter { $0.frame.intersects(rect) }
    }

    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let items = enabled ? displayedAttributes() : resting
        return items.indices.contains(indexPath.item) ? items[indexPath.item] : nil
    }

    public override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        layoutAttributesForItem(at: itemIndexPath)
    }

    public override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        layoutAttributesForItem(at: itemIndexPath)
    }

    private func projectedFrames(_ frames: [CGRect]) -> [CGRect] {
        let anchor = frames.indices.min { abs(frames[$0].midY - touch.y) < abs(frames[$1].midY - touch.y) } ?? 0
        let settings = configuration.normalized
        return MotionGeometry.projectMinimumGap(frames, anchor: anchor,
            normalGap: CGFloat(settings.normalGap), minimumRatio: CGFloat(settings.minimumGapRatio))
    }

    private func displayedAttributes() -> [UICollectionViewLayoutAttributes] {
        let frames = projectedFrames(resting.enumerated().map { index, base in
            springs.indices.contains(index) ? springs[index].item.frame : base.frame
        })
        return zip(resting, frames).map { base, frame in
            let attributes = base.copy() as! UICollectionViewLayoutAttributes
            attributes.frame = frame
            return attributes
        }
    }

    private func constrainMinimumGap(updateAnimator: Bool) {
        let items = springs.map(\.item)
        for (item, frame) in zip(items, projectedFrames(items.map(\.frame))) where item.frame != frame {
            item.frame = frame
            if updateAnimator { animator.updateItem(usingCurrentState: item) }
        }
    }

    private func updateSpringSettings() {
        let settings = configuration.normalized
        for spring in springs {
            if abs(spring.attachment.frequency - CGFloat(settings.frequency)) > 0.0001 {
                spring.attachment.frequency = CGFloat(settings.frequency)
            }
            if abs(spring.attachment.damping - CGFloat(settings.damping)) > 0.0001 {
                spring.attachment.damping = CGFloat(settings.damping)
            }
        }
    }

    private func installAction() {
        guard let first = springs.first, first.attachment.action == nil else { return }
        first.attachment.action = { [weak self] in
            guard let self else { return }
            self.constrainMinimumGap(updateAnimator: true)
            self.invalidateLayout()
        }
    }

    public override func shouldInvalidateLayout(forBoundsChange proposed: CGRect) -> Bool {
        guard let collectionView else { return true }
        let previous = collectionView.bounds
        let widthChanged = abs(proposed.width - previous.width) > 0.25
        let minimum = -collectionView.adjustedContentInset.top
        let maximum = max(minimum, height + collectionView.adjustedContentInset.bottom - proposed.height)
        let settings = configuration.normalized
        let state = MotionGeometry.InputState(dragging: dragging, coasting: coasting,
            decelerating: collectionView.isDecelerating, enabled: enabled, rebasing: rebasing,
            sizeChanged: proposed.size != previous.size, coastInjection: settings.deformsDuringDeceleration)
        guard state.acceptsInput(proposedY: proposed.minY, minimumY: minimum, maximumY: maximum) else {
            // Height changes belong to keyboardLayoutGuide, not animated layout transitions.
            return widthChanged
        }
        let delta = proposed.minY - previous.minY
        guard delta.isFinite, delta != 0 else { return false }
        if dragging {
            touch = collectionView.panGestureRecognizer.location(in: collectionView)
            releaseTouchOnScreen = CGPoint(x: touch.x - previous.minX, y: touch.y - previous.minY)
        } else {
            touch = CGPoint(x: releaseTouchOnScreen.x + previous.minX, y: releaseTouchOnScreen.y + previous.minY)
        }
        for spring in springs {
            spring.item.center.y += MotionGeometry.displacement(delta: delta,
                anchor: spring.item.restingCenter, touch: touch, strength: CGFloat(settings.dragStrength))
        }
        constrainMinimumGap(updateAnimator: false)
        for spring in springs { animator.updateItem(usingCurrentState: spring.item) }
        // The native action publishes the continuous positions as layout attributes.
        return false
    }

    public func beginDragging() {
        dragging = true
        coasting = false
        installAction()
        updateSpringSettings()
        constrainMinimumGap(updateAnimator: true)
    }

    public func endDragging(willDecelerate: Bool) {
        dragging = false
        coasting = willDecelerate
    }

    public func endScrolling() { coasting = false }

    /// The scroll view should first stop its native momentum at initial contact.
    public func interruptOnTouchDown(at point: CGPoint) {
        dragging = false
        coasting = false
        guard enabled, let collectionView else { return }
        touch = point
        releaseTouchOnScreen = CGPoint(x: point.x - collectionView.bounds.minX, y: point.y - collectionView.bounds.minY)
        constrainMinimumGap(updateAnimator: false)
        let nearest = layoutAttributesForElements(in: collectionView.bounds)?.min {
            abs($0.center.y - point.y) < abs($1.center.y - point.y)
        }
        let lag = nearest.flatMap { item in restingFrame(at: item.indexPath).map { item.center.y - $0.midY } } ?? 0
        let offset = collectionView.contentOffset
        let minimum = -collectionView.adjustedContentInset.top
        let maximum = max(minimum, height + collectionView.adjustedContentInset.bottom - collectionView.bounds.height)
        let target = MotionGeometry.rebasedOffset(offset: offset.y, lag: lag, minimum: minimum, maximum: maximum)
        let correction = target - offset.y

        animator.delegate = nil
        animator.removeAllBehaviors()
        animator = makeAnimator()
        springs = springs.enumerated().map { index, old in
            old.item.center.y += correction
            return Spring(item: old.item, attachment: makeAttachment(old.item, anchor: resting[index].center))
        }
        rebasing = true
        defer { rebasing = false }
        UIView.performWithoutAnimation {
            collectionView.contentOffset = CGPoint(x: offset.x, y: target)
            invalidateLayout()
            collectionView.layoutIfNeeded()
        }
        for spring in springs { animator.addBehavior(spring.attachment) }
        installAction()
    }

    public func dynamicAnimatorDidPause(_ animator: UIDynamicAnimator) {
        guard animator === self.animator else { return }
        for spring in springs { spring.item.center = spring.item.restingCenter }
        invalidateLayout()
    }

    public func reset() {
        animator.delegate = nil
        animator.removeAllBehaviors()
        animator = makeAnimator()
        springs.removeAll()
        dragging = false
        coasting = false
        touch = .zero
        releaseTouchOnScreen = .zero
        invalidateLayout()
    }
}
#endif
