#if canImport(UIKit)
import XCTest
@testable import MessageMotion

@MainActor
final class ReturnScrollTests: XCTestCase {
    func testRetargetCancellationAndCompletion() {
        let driver = ReturnToLatestDriver()
        var target: CGFloat = 800
        var output: CGFloat = -1
        var completions = 0
        driver.start(from: 0, latest: { target }, setOffset: { output = $0 },
                     completion: { completions += 1 }, at: 0)
        driver.step(at: 0.175)
        XCTAssertEqual(output, 700, accuracy: 0.000001)
        target = 1000
        driver.step(at: 0.175)
        XCTAssertEqual(output, 875, accuracy: 0.000001)
        driver.cancel()
        driver.step(at: 0.35)
        XCTAssertEqual(output, 875)
        XCTAssertEqual(completions, 0)
        XCTAssertFalse(driver.isRunning)
        driver.start(from: output, latest: { target }, setOffset: { output = $0 },
                     completion: { completions += 1 }, at: 1)
        driver.step(at: 1.35)
        XCTAssertEqual(output, 1000, accuracy: 0.000001)
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(driver.isRunning)
    }

    func testDisplayLinkDoesNotRetainDriver() {
        weak var reference: ReturnToLatestDriver?
        do {
            let driver = ReturnToLatestDriver()
            reference = driver
            driver.start(from: 0, latest: { 800 }, setOffset: { _ in }, completion: {}, at: 0)
        }
        XCTAssertNil(reference)
    }
}
#endif
