import XCTest
@testable import FeatureHome

@MainActor
final class ArtworkPrefetchTrackerTests: XCTestCase {
    func testCellCompletionOrderCannotReverseAStationaryViewport() {
        let tracker = ArtworkPrefetchTracker()
        tracker.updateDirection(at: 0)
        tracker.updateDirection(at: 2_000)
        for index in [41, 12, 35, 6, 29, 0] {
            tracker.updateDirection(at: 2_000)
            tracker.seen.insert("\(index)")
        }
        XCTAssertTrue(tracker.forward)
        XCTAssertEqual(tracker.seen.count, 6)
        XCTAssertTrue(tracker.seenBackward.isEmpty)
    }

    func testSmallViewportReversalWarmsTheReturnPassAgain() {
        let tracker = ArtworkPrefetchTracker()
        tracker.updateDirection(at: 0)
        tracker.updateDirection(at: 2_000)
        tracker.seen.insert("forward")
        tracker.seenBackward.insert("evicted")
        tracker.updateDirection(at: 1_999)
        XCTAssertFalse(tracker.forward)
        XCTAssertTrue(tracker.seenBackward.isEmpty)
        XCTAssertEqual(tracker.seen, ["forward"])
        tracker.seenBackward.insert("return")
        tracker.updateDirection(at: 1_998)
        XCTAssertEqual(tracker.seenBackward, ["return"])
        tracker.updateDirection(at: 1_999)
        XCTAssertTrue(tracker.forward)
        XCTAssertTrue(tracker.seen.isEmpty)
        XCTAssertEqual(tracker.seenBackward, ["return"])
    }
}
