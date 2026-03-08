import XCTest

class ProcessTableTests: XCTestCase {

    // MARK: - Parse

    func testParseBasicOutput() {
        let output = """
          PID  PPID  %CPU ARGS
            1     0   0.1 /sbin/launchd
          100     1   2.5 /usr/bin/claude --flag
          101   100   0.0 /bin/bash
        """
        let table = ProcessTable.parse(psOutput: output)

        XCTAssertEqual(table.count, 3)

        XCTAssertEqual(table[1]?.ppid, 0)
        XCTAssertEqual(table[1]!.cpu, 0.1, accuracy: 0.01)
        XCTAssertEqual(table[1]?.command, "/sbin/launchd")

        XCTAssertEqual(table[100]?.ppid, 1)
        XCTAssertEqual(table[100]!.cpu, 2.5, accuracy: 0.01)
        XCTAssertEqual(table[100]?.command, "/usr/bin/claude --flag")

        XCTAssertEqual(table[101]?.ppid, 100)
    }

    func testParseSkipsHeader() {
        let output = """
          PID  PPID  %CPU ARGS
           42     1   1.0 /usr/bin/test
        """
        let table = ProcessTable.parse(psOutput: output)

        XCTAssertEqual(table.count, 1)
        XCTAssertNotNil(table[42])
        // PID "PID" should not appear
        XCTAssertNil(table[0])
    }

    func testParseEmptyOutput() {
        let table = ProcessTable.parse(psOutput: "")
        XCTAssertTrue(table.isEmpty)
    }

    func testParseHeaderOnly() {
        let table = ProcessTable.parse(psOutput: "  PID  PPID  %CPU ARGS")
        XCTAssertTrue(table.isEmpty)
    }

    func testParseCommandWithSpaces() {
        let output = """
          PID  PPID  %CPU ARGS
          200     1   3.0 /Applications/Visual Studio Code.app/Contents/MacOS/Electron --some-flag
        """
        let table = ProcessTable.parse(psOutput: output)

        XCTAssertEqual(table[200]?.command,
                       "/Applications/Visual Studio Code.app/Contents/MacOS/Electron --some-flag")
    }

    // MARK: - Descendants

    func testDescendantsSimpleChain() {
        // 1 -> 2 -> 3
        let table: [Int32: ProcessInfo] = [
            1: ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "root"),
            2: ProcessInfo(pid: 2, ppid: 1, cpu: 1, command: "child"),
            3: ProcessInfo(pid: 3, ppid: 2, cpu: 2, command: "grandchild"),
        ]

        let desc = ProcessTable.descendants(of: 1, in: table)
        let pids = Set(desc.map(\.pid))
        XCTAssertEqual(pids, [2, 3])
    }

    func testDescendantsFanOut() {
        // 1 -> 2, 1 -> 3, 1 -> 4
        let table: [Int32: ProcessInfo] = [
            1: ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "root"),
            2: ProcessInfo(pid: 2, ppid: 1, cpu: 0, command: "c1"),
            3: ProcessInfo(pid: 3, ppid: 1, cpu: 0, command: "c2"),
            4: ProcessInfo(pid: 4, ppid: 1, cpu: 0, command: "c3"),
        ]

        let desc = ProcessTable.descendants(of: 1, in: table)
        XCTAssertEqual(desc.count, 3)
    }

    func testDescendantsNoChildren() {
        let table: [Int32: ProcessInfo] = [
            1: ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "root"),
            2: ProcessInfo(pid: 2, ppid: 0, cpu: 0, command: "other"),
        ]

        let desc = ProcessTable.descendants(of: 1, in: table)
        XCTAssertTrue(desc.isEmpty)
    }

    func testDescendantsDoesNotIncludeRoot() {
        let table: [Int32: ProcessInfo] = [
            1: ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "root"),
            2: ProcessInfo(pid: 2, ppid: 1, cpu: 0, command: "child"),
        ]

        let desc = ProcessTable.descendants(of: 1, in: table)
        XCTAssertFalse(desc.contains(where: { $0.pid == 1 }),
                       "Descendants should not include the root PID itself")
    }

    func testDescendantsDeepNesting() {
        // 1 -> 2 -> 3 -> 4 -> 5
        var table: [Int32: ProcessInfo] = [:]
        for i: Int32 in 1...5 {
            table[i] = ProcessInfo(pid: i, ppid: i - 1, cpu: 0, command: "p\(i)")
        }

        let desc = ProcessTable.descendants(of: 1, in: table)
        XCTAssertEqual(desc.count, 4) // 2,3,4,5
    }

    // MARK: - AI Process Matching

    func testMatchesDirectClaude() {
        XCTAssertTrue(ProcessTable.matchesAIProcess("claude"))
    }

    func testMatchesClaudeWithPath() {
        XCTAssertTrue(ProcessTable.matchesAIProcess("/usr/local/bin/claude --flag"))
    }

    func testMatchesNodeGemini() {
        XCTAssertTrue(ProcessTable.matchesAIProcess("node /opt/homebrew/bin/gemini"))
    }

    func testMatchesCodex() {
        XCTAssertTrue(ProcessTable.matchesAIProcess("/usr/bin/codex"))
    }

    func testMatchesAntigravity() {
        XCTAssertTrue(ProcessTable.matchesAIProcess("/path/to/language_server_macos_arm"))
    }

    func testRejectsElectronGPUProcess() {
        XCTAssertFalse(ProcessTable.matchesAIProcess(
            "/Applications/Claude.app/Contents/Frameworks/Claude Helper (GPU).app/Contents/MacOS/Claude Helper (GPU) --type=gpu-process"
        ))
    }

    func testRejectsElectronRenderer() {
        XCTAssertFalse(ProcessTable.matchesAIProcess(
            "/Applications/Claude.app/Contents/MacOS/Claude --type=renderer"
        ))
    }

    func testRejectsElectronUtility() {
        XCTAssertFalse(ProcessTable.matchesAIProcess(
            "/path/to/Claude --type=utility"
        ))
    }

    func testRejectsUnknownProcess() {
        XCTAssertFalse(ProcessTable.matchesAIProcess("vim"))
        XCTAssertFalse(ProcessTable.matchesAIProcess("/usr/bin/bash"))
        XCTAssertFalse(ProcessTable.matchesAIProcess("node /path/to/server.js"))
    }

    func testMatchesCaseInsensitive() {
        // AI names are lowercased in the matching
        XCTAssertTrue(ProcessTable.matchesAIProcess("/path/to/Claude"))
    }

    // MARK: - Executable Basename

    func testExecutableBasenameSimple() {
        XCTAssertEqual(ProcessTable.executableBasename(from: "claude"), "claude")
    }

    func testExecutableBasenameWithPath() {
        XCTAssertEqual(ProcessTable.executableBasename(from: "/usr/bin/claude"), "claude")
    }

    func testExecutableBasenameWithArgs() {
        XCTAssertEqual(ProcessTable.executableBasename(from: "claude --flag --verbose"), "claude")
    }

    func testExecutableBasenameWithPathAndArgs() {
        XCTAssertEqual(ProcessTable.executableBasename(from: "/usr/local/bin/node script.js"), "node")
    }

    // MARK: - Find AI Processes

    func testFindAIProcessesInMixedTable() {
        let table: [Int32: ProcessInfo] = [
            1: ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "/sbin/launchd"),
            2: ProcessInfo(pid: 2, ppid: 1, cpu: 5, command: "/usr/bin/claude --work"),
            3: ProcessInfo(pid: 3, ppid: 1, cpu: 0, command: "/bin/bash"),
            4: ProcessInfo(pid: 4, ppid: 1, cpu: 3, command: "node /opt/homebrew/bin/gemini"),
            5: ProcessInfo(pid: 5, ppid: 2, cpu: 0, command: "/usr/bin/git status"),
        ]

        let found = ProcessTable.findAIProcesses(in: table)
        let pids = Set(found.map(\.pid))
        XCTAssertEqual(pids, [2, 4])
    }

    func testFindAIProcessesEmpty() {
        let table: [Int32: ProcessInfo] = [
            1: ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "/bin/bash"),
        ]
        XCTAssertTrue(ProcessTable.findAIProcesses(in: table).isEmpty)
    }
}
