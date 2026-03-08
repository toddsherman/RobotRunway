import XCTest

class ShellTests: XCTestCase {

    func testSimpleCommand() {
        let result = Shell.run("echo", "hello")
        XCTAssertEqual(result, "hello")
    }

    func testCommandWithMultipleArgs() {
        let result = Shell.run("echo", "hello", "world")
        XCTAssertEqual(result, "hello world")
    }

    func testNonexistentCommandReturnsEmpty() {
        let result = Shell.run("__nonexistent_command_xyz__")
        XCTAssertEqual(result, "")
    }

    func testTimeoutKillsLongProcess() {
        let start = Date()
        let result = Shell.run(["sleep", "30"], timeout: 1)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result, "", "Timed-out process should return empty string")
        XCTAssertLessThan(elapsed, 5.0,
                          "Should not wait the full 30 seconds (timeout at 1s)")
    }

    func testNormalCommandCompletesBeforeTimeout() {
        let result = Shell.run(["echo", "fast"], timeout: 10)
        XCTAssertEqual(result, "fast")
    }

    func testOutputIsTrimmed() {
        let result = Shell.run("echo", "")
        // echo "" produces a newline, which should be trimmed
        XCTAssertEqual(result, "")
    }

    func testArrayRunVariant() {
        let result = Shell.run(["echo", "array", "variant"])
        XCTAssertEqual(result, "array variant")
    }

    func testLargeOutput() {
        // Generate output larger than typical pipe buffer
        let result = Shell.run("seq", "1", "10000")
        XCTAssertFalse(result.isEmpty, "Should handle large output without deadlock")
        XCTAssertTrue(result.contains("10000"))
    }
}
