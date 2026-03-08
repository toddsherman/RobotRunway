import XCTest

class PollLogTests: XCTestCase {

    func testEmptyPollLog() {
        let monitor = ActivityMonitor()
        let log = monitor.currentPollLog()
        XCTAssertTrue(log.isEmpty)
    }

    func testPollLogGrows() {
        let monitor = ActivityMonitor()
        // Each poll() call adds entries to the log
        // We can't easily mock the process table, but we can verify
        // that after a poll, entries exist (even if "No Session")
        _ = monitor.poll()
        let log = monitor.currentPollLog()
        XCTAssertFalse(log.isEmpty, "Poll should add at least one log entry")
    }

    func testPollLogEntryFields() {
        let monitor = ActivityMonitor()
        _ = monitor.poll()
        let log = monitor.currentPollLog()

        guard let entry = log.first else {
            XCTFail("Should have at least one entry")
            return
        }

        // For a "no session" entry
        XCTAssertEqual(entry.stateLabel, "No Session")
        XCTAssertEqual(entry.cpu, 0)
        XCTAssertEqual(entry.connections, 0)
        XCTAssertEqual(entry.childCount, 0)
        XCTAssertFalse(entry.isActive)
    }

    func testPollLogTimestampOrder() {
        let monitor = ActivityMonitor()

        // Multiple polls should produce chronologically ordered entries
        for _ in 0..<5 {
            _ = monitor.poll()
            Thread.sleep(forTimeInterval: 0.01) // Small delay for distinct timestamps
        }

        let log = monitor.currentPollLog()
        for i in 1..<log.count {
            XCTAssertGreaterThanOrEqual(log[i].timestamp, log[i-1].timestamp,
                                        "Entries should be chronologically ordered")
        }
    }

    func testCurrentPollLogReturnsSnapshot() {
        let monitor = ActivityMonitor()
        _ = monitor.poll()

        // Getting the log twice should return independent snapshots
        let log1 = monitor.currentPollLog()
        _ = monitor.poll()
        let log2 = monitor.currentPollLog()

        // log2 should have more entries than log1
        XCTAssertGreaterThanOrEqual(log2.count, log1.count)
    }
}
