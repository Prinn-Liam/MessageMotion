// SPDX-License-Identifier: MIT
#if canImport(UIKit)
import SwiftUI
import UIKit

@MainActor
final class MotionTranscriptController<Message: Identifiable & Equatable, Bubble: View, Composer: View>: UIViewController,
    UICollectionViewDelegate, UIGestureRecognizerDelegate where Message.ID: Sendable {
    private var content: MotionChat<Message, Bubble, Composer>
    private var environment: EnvironmentValues
    private var reduceMotion: Bool
    private let layout = MessageMotionLayout()
    private lazy var collectionView = MotionCollectionView(frame: .zero, collectionViewLayout: layout)
    private let composerHost: UIHostingController<MotionHostedContent<Composer>>
    private let measurementHost = UIHostingController(rootView: AnyView(EmptyView()))
    private var dataSource: UICollectionViewDiffableDataSource<Int, Message.ID>!
    private var messages: [Message.ID: Message] = [:]
    private var ids: [Message.ID] = []
    private var followsLatest = true
    private var hasPositioned = false
    private var wasComposing = false
    private var pendingFocusReturn = false
    private var userScrolling = false
    private var focusFallback: Task<Void, Never>?
    private var generation = 0
    private let returnScroll = ReturnToLatestDriver()

    private struct Measurement {
        let message: Message
        let width: CGFloat
        let last: Bool
        let gap: Double
        let typeSize: DynamicTypeSize
        let height: CGFloat
    }
    private var measurements: [Message.ID: Measurement] = [:]
    private var measurementsDirty = true
    private var measuredWidth: CGFloat = 0
    private lazy var touchObserver: UITapGestureRecognizer = {
        let observer = UITapGestureRecognizer(target: nil, action: nil)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.delegate = self
        return observer
    }()

    init(content: MotionChat<Message, Bubble, Composer>, environment: EnvironmentValues, reduceMotion: Bool) {
        self.content = content
        self.environment = environment
        self.reduceMotion = reduceMotion
        composerHost = UIHostingController(rootView: MotionHostedContent(content: content.composer, environment: environment))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use MotionChat to create this controller") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = UIEdgeInsets(top: 16, left: 0, bottom: 12, right: 0)
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.showsVerticalScrollIndicator = false
        collectionView.accessibilityIdentifier = "message-motion.transcript"
        collectionView.delegate = self
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "message")
        collectionView.onLayout = { [weak self] in
            self?.measureRows()
            self?.maintainViewport()
        }
        collectionView.onAccessibilityScroll = { [weak self] in
            self?.followsLatest = false
            self?.userScrolling = true
        }
        collectionView.addGestureRecognizer(touchObserver)
        let dismiss = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismiss.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(dismiss)

        addChild(composerHost)
        composerHost.safeAreaRegions = []
        composerHost.sizingOptions = .intrinsicContentSize
        composerHost.view.backgroundColor = .clear
        view.addSubview(collectionView)
        view.addSubview(composerHost.view)
        composerHost.didMove(toParent: self)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        composerHost.view.translatesAutoresizingMaskIntoConstraints = false
        composerHost.view.setContentHuggingPriority(.required, for: .vertical)
        composerHost.view.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: composerHost.view.topAnchor),
            composerHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerHost.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        dataSource = UICollectionViewDiffableDataSource<Int, Message.ID>(collectionView: collectionView) { [weak self] view, path, id in
            guard let self, let message = self.messages[id] else { return nil }
            let cell = view.dequeueReusableCell(withReuseIdentifier: "message", for: path)
            cell.backgroundColor = .clear
            cell.contentConfiguration = UIHostingConfiguration {
                self.row(message).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.margins(.all, 0).minSize(height: 0)
            return cell
        }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        update(content: content, environment: environment, reduceMotion: reduceMotion)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = composerHost.view.bounds.height
        if abs(view.keyboardLayoutGuide.keyboardDismissPadding - height) > 0.25 {
            view.keyboardLayoutGuide.keyboardDismissPadding = height
        }
    }

    func update(content: MotionChat<Message, Bubble, Composer>, environment: EnvironmentValues, reduceMotion: Bool) {
        if content.layoutRevision != self.content.layoutRevision { measurements.removeAll() }
        self.content = content
        self.environment = environment
        self.reduceMotion = reduceMotion
        guard isViewLoaded else { return }
        layout.configuration = content.configuration
        layout.enabled = !reduceMotion && !content.isComposing
        composerHost.rootView = MotionHostedContent(content: content.composer, environment: environment)

        let newIDs = content.messages.map(\.id)
        let follow = !hasPositioned || MotionGeometry.shouldFollow(previousLatest: ids.last, latest: newIDs.last,
            nearBottom: latestOffset - collectionView.contentOffset.y <= max(16, content.configuration.normalized.normalGap),
            outgoing: content.messages.last.map(content.outgoing) ?? false)
        let anchor = collectionView.indexPathsForVisibleItems.sorted().compactMap { path -> (Message.ID, CGFloat)? in
            guard let id = dataSource.itemIdentifier(for: path), let frame = layout.restingFrame(at: path) else { return nil }
            return (id, frame.minY - collectionView.contentOffset.y)
        }.first
        let changed = newIDs != ids
        if changed { layout.reset() }
        messages = Dictionary(uniqueKeysWithValues: content.messages.map { ($0.id, $0) })
        ids = newIDs
        measurementsDirty = true
        measureRows()
        if follow { followsLatest = true }
        generation += 1
        let currentGeneration = generation
        var snapshot = NSDiffableDataSourceSnapshot<Int, Message.ID>()
        snapshot.appendSections([0])
        snapshot.appendItems(newIDs)
        if hasPositioned {
            let retained = Set(newIDs)
            snapshot.reconfigureItems(collectionView.indexPathsForVisibleItems.compactMap {
                dataSource.itemIdentifier(for: $0)
            }.filter { retained.contains($0) })
        }
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, currentGeneration == self.generation else { return }
            self.collectionView.layoutIfNeeded()
            if self.followsLatest {
                if !self.hasPositioned, !self.userScrolling, let last = self.ids.last,
                   let path = self.dataSource.indexPath(for: last) {
                    self.collectionView.scrollToItem(at: path, at: .bottom, animated: false)
                    self.collectionView.layoutIfNeeded()
                }
                self.positionAtLatest()
            } else if changed, let (id, relativeY) = anchor, let path = self.dataSource.indexPath(for: id),
                      let frame = self.layout.restingFrame(at: path) {
                self.collectionView.contentOffset.y = frame.minY - relativeY
            }
            self.hasPositioned = true
        }

        if content.isComposing, !wasComposing, !followsLatest {
            pendingFocusReturn = true
            layout.reset()
            focusFallback?.cancel()
            focusFallback = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, self.pendingFocusReturn, self.content.isComposing else { return }
                self.returnToLatest(keyboardDuration: 0.25, options: .curveEaseOut)
            }
        } else if !content.isComposing {
            pendingFocusReturn = false
            focusFallback?.cancel()
        }
        wasComposing = content.isComposing
    }

    private var latestOffset: CGFloat {
        max(-collectionView.contentInset.top,
            collectionView.contentSize.height + collectionView.contentInset.bottom - collectionView.bounds.height)
    }

    private func positionAtLatest() {
        guard collectionView.bounds.height > 0, !userScrolling, !returnScroll.isRunning else { return }
        if abs(collectionView.contentOffset.y - latestOffset) > 0.25 { collectionView.contentOffset.y = latestOffset }
    }

    private func maintainViewport() {
        let top = max(16, collectionView.bounds.height - collectionView.contentSize.height - collectionView.contentInset.bottom)
        if abs(collectionView.contentInset.top - top) > 0.25 { collectionView.contentInset.top = top }
        if followsLatest, !userScrolling, !collectionView.isTracking, !collectionView.isDecelerating { positionAtLatest() }
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard view.window != nil, pendingFocusReturn, content.isComposing else { return }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        returnToLatest(keyboardDuration: duration, options: UIView.AnimationOptions(rawValue: curve << 16))
    }

    private func returnToLatest(keyboardDuration: Double, options: UIView.AnimationOptions) {
        pendingFocusReturn = false
        focusFallback?.cancel()
        userScrolling = false
        guard !reduceMotion, view.window != nil else {
            returnScroll.cancel()
            followsLatest = true
            UIView.performWithoutAnimation { view.layoutIfNeeded(); positionAtLatest() }
            return
        }
        followsLatest = false
        UIView.animate(withDuration: keyboardDuration, delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction]) { self.view.layoutIfNeeded() }
        returnScroll.cancel()
        var start = collectionView.contentOffset.y
        let longest = collectionView.bounds.height * 6
        if latestOffset - start > longest {
            start = latestOffset - longest
            UIView.performWithoutAnimation { collectionView.contentOffset.y = start }
        }
        guard abs(latestOffset - start) > 0.5 else {
            followsLatest = true
            positionAtLatest()
            return
        }
        returnScroll.start(from: start, latest: { [weak self] in self?.latestOffset ?? start },
            setOffset: { [weak self] y in UIView.performWithoutAnimation { self?.collectionView.contentOffset.y = y } },
            completion: { [weak self] in self?.followsLatest = true; self?.positionAtLatest() })
    }

    private func row(_ message: Message) -> some View {
        content.bubble(message).environment(\.self, environment)
            .padding(.bottom, message.id == ids.last ? 0 : content.configuration.normalized.normalGap)
    }

    private func measureRows() {
        let width = collectionView.bounds.width
        guard width > 0, measurementsDirty || abs(width - measuredWidth) > 0.25 else { return }
        measuredWidth = width
        measurementsDirty = false
        let gap = content.configuration.normalized.normalGap
        let typeSize = environment.dynamicTypeSize
        let heights = content.messages.map { message -> CGFloat in
            let last = message.id == ids.last
            if let cached = measurements[message.id], cached.message == message, cached.width == width,
               cached.last == last, cached.gap == gap, cached.typeSize == typeSize { return cached.height }
            measurementHost.rootView = AnyView(MotionHostedContent(content: row(message), environment: environment))
            let raw = measurementHost.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let scale = max(1, environment.displayScale)
            let height = max(1, ceil(raw * scale) / scale)
            measurements[message.id] = Measurement(message: message, width: width, last: last, gap: gap,
                typeSize: typeSize, height: height)
            return height
        }
        let retained = Set(ids)
        measurements = measurements.filter { retained.contains($0.key) }
        layout.setItemHeights(heights, width: width)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        UIView.performWithoutAnimation { cell.layoutIfNeeded() }
        func strip(_ layer: CALayer) { layer.removeAllAnimations(); layer.sublayers?.forEach(strip) }
        strip(cell.layer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === touchObserver else { return true }
        cancelFocusReturn()
        followsLatest = latestOffset - collectionView.contentOffset.y <= 0.5
        userScrolling = false
        if collectionView.isDecelerating || collectionView.isScrollAnimating { collectionView.stopScrollingAndZooming() }
        layout.interruptOnTouchDown(at: touch.location(in: collectionView))
        return false
    }

    private func cancelFocusReturn() {
        pendingFocusReturn = false
        focusFallback?.cancel()
        returnScroll.cancel()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        layout.beginDragging()
        cancelFocusReturn()
        followsLatest = false
        userScrolling = true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard userScrolling || scrollView.isDragging || scrollView.isDecelerating else { return }
        followsLatest = latestOffset - collectionView.contentOffset.y <= 0.5
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        layout.endDragging(willDecelerate: decelerate)
        userScrolling = decelerate
        followsLatest = latestOffset - collectionView.contentOffset.y <= 0.5
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        layout.endScrolling()
        userScrolling = false
        followsLatest = latestOffset - collectionView.contentOffset.y <= 0.5
    }

    @objc private func dismissKeyboard() { composerHost.view.endEditing(true) }

    func stop() {
        cancelFocusReturn()
        layout.reset()
        collectionView.onLayout = nil
        collectionView.onAccessibilityScroll = nil
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
private final class MotionCollectionView: UICollectionView {
    var onLayout: (() -> Void)?
    var onAccessibilityScroll: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        onAccessibilityScroll?()
        return super.accessibilityScroll(direction)
    }
}
#endif
