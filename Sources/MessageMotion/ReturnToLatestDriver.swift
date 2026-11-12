// SPDX-License-Identifier: MIT
#if canImport(UIKit)
import UIKit

@MainActor
final class ReturnToLatestDriver {
    private var link: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var from: CGFloat = 0
    private var latest: (() -> CGFloat)?
    private var setOffset: ((CGFloat) -> Void)?
    private var completion: (() -> Void)?
    private let duration: CFTimeInterval = 0.35
    var isRunning: Bool { link != nil }

    func start(from: CGFloat, latest: @escaping () -> CGFloat, setOffset: @escaping (CGFloat) -> Void,
               completion: @escaping () -> Void, at time: CFTimeInterval = CACurrentMediaTime()) {
        cancel()
        self.from = from
        self.latest = latest
        self.setOffset = setOffset
        self.completion = completion
        startedAt = time
        let target = ReturnScrollTarget(owner: self)
        let link = CADisplayLink(target: target, selector: #selector(ReturnScrollTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    func step(at time: CFTimeInterval) {
        guard isRunning, let latest else { return }
        let progress = min(1, max(0, (time - startedAt) / duration))
        setOffset?(MotionGeometry.returnOffset(from: from, latest: latest(), progress: progress))
        if progress >= 1 {
            let finished = completion
            cancel()
            finished?()
        }
    }

    func cancel() {
        link?.invalidate()
        link = nil
        latest = nil
        setOffset = nil
        completion = nil
    }
}

@MainActor
private final class ReturnScrollTarget: NSObject {
    weak var owner: ReturnToLatestDriver?
    init(owner: ReturnToLatestDriver) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        owner.step(at: link.targetTimestamp)
    }
}
#endif
