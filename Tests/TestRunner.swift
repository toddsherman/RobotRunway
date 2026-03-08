import XCTest

// ─────────────────────────────────────────────────────────
// XCTest entry point for swiftc-compiled test binary.
// Uses @main attribute to designate this as the entry point.
// ─────────────────────────────────────────────────────────

@main
struct TestRunner {
    static func main() {
        let testSuite = XCTestSuite.default
        testSuite.run()

        guard let testRun = testSuite.testRun else {
            print("❌ No test run results")
            exit(1)
        }

        let failed = Int(testRun.failureCount) + Int(testRun.unexpectedExceptionCount)

        print("")
        print("═══════════════════════════════════════")
        if failed == 0 {
            print("✅ All \(testRun.testCaseCount) tests passed")
        } else {
            print("❌ \(failed) of \(testRun.testCaseCount) tests failed")
        }
        print("   Duration: \(String(format: "%.2f", testRun.testDuration))s")
        print("═══════════════════════════════════════")

        exit(failed == 0 ? 0 : 1)
    }
}
