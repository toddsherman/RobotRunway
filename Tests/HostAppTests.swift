import XCTest

class HostAppTests: XCTestCase {

    // MARK: - matchHostApp

    func testMatchSingleWordName() {
        let apps = [
            HostApp(id: "terminal", displayName: "Terminal",
                    processNames: ["Terminal"], bundleIdentifier: nil, isElectron: false),
        ]

        let result = HostAppRegistry.matchHostApp(
            command: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
            in: apps
        )
        XCTAssertEqual(result?.id, "terminal")
    }

    func testMatchMultiWordName() {
        let apps = [
            HostApp(id: "vscode", displayName: "VS Code",
                    processNames: ["Code Helper"], bundleIdentifier: nil, isElectron: true),
        ]

        let result = HostAppRegistry.matchHostApp(
            command: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Renderer).app/Contents/MacOS/Code Helper (Renderer)",
            in: apps
        )
        // This should match via contains("/Code Helper")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "vscode")
    }

    func testMatchMultiWordAtPrefix() {
        let apps = [
            HostApp(id: "vscode", displayName: "VS Code",
                    processNames: ["Code Helper"], bundleIdentifier: nil, isElectron: true),
        ]

        let result = HostAppRegistry.matchHostApp(
            command: "Code Helper --renderer",
            in: apps
        )
        XCTAssertEqual(result?.id, "vscode")
    }

    func testNoMatchReturnsNil() {
        let apps = [
            HostApp(id: "terminal", displayName: "Terminal",
                    processNames: ["Terminal"], bundleIdentifier: nil, isElectron: false),
        ]

        let result = HostAppRegistry.matchHostApp(
            command: "/usr/bin/vim", in: apps
        )
        XCTAssertNil(result)
    }

    func testMatchEmptyApps() {
        let result = HostAppRegistry.matchHostApp(
            command: "/usr/bin/claude", in: []
        )
        XCTAssertNil(result)
    }

    func testMatchMultipleProcessNames() {
        let apps = [
            HostApp(id: "cursor", displayName: "Cursor",
                    processNames: ["Cursor", "Cursor Helper"], bundleIdentifier: nil, isElectron: true),
        ]

        let r1 = HostAppRegistry.matchHostApp(command: "/path/to/Cursor", in: apps)
        XCTAssertEqual(r1?.id, "cursor")

        let r2 = HostAppRegistry.matchHostApp(command: "/path/to/Cursor Helper --renderer", in: apps)
        XCTAssertEqual(r2?.id, "cursor")
    }

    // MARK: - hostApp(forProcessID:)

    func testHostAppTreeWalk() {
        // Process tree: launchd(1) -> Terminal(50) -> bash(100) -> claude(200)
        let table: [Int32: ProcessInfo] = [
            1:   ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "/sbin/launchd"),
            50:  ProcessInfo(pid: 50, ppid: 1, cpu: 0,
                             command: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            100: ProcessInfo(pid: 100, ppid: 50, cpu: 0, command: "/bin/bash"),
            200: ProcessInfo(pid: 200, ppid: 100, cpu: 5, command: "/usr/bin/claude"),
        ]

        // Enable Terminal for this test
        UserDefaults.standard.set(true, forKey: "hostApp.enabled.terminal")
        HostAppRegistry.invalidateCache()

        let result = HostAppRegistry.hostApp(forProcessID: 200, processTable: table)
        XCTAssertEqual(result?.app.id, "terminal")
        XCTAssertEqual(result?.pid, 50)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "hostApp.enabled.terminal")
        HostAppRegistry.invalidateCache()
    }

    func testHostAppOrphanProcess() {
        // Process whose parent tree doesn't contain any host app
        let table: [Int32: ProcessInfo] = [
            1:   ProcessInfo(pid: 1, ppid: 0, cpu: 0, command: "/sbin/launchd"),
            200: ProcessInfo(pid: 200, ppid: 1, cpu: 5, command: "/usr/bin/claude"),
        ]

        let result = HostAppRegistry.hostApp(forProcessID: 200, processTable: table)
        XCTAssertNil(result, "Should not match when no host app in parent chain")
    }

    // MARK: - Cache Invalidation

    func testCacheInvalidation() {
        // Set up known state
        let key = "hostApp.enabled.terminal"
        UserDefaults.standard.set(true, forKey: key)
        HostAppRegistry.invalidateCache()

        let enabled1 = HostAppRegistry.enabledApps
        let hasTerminal1 = enabled1.contains { $0.id == "terminal" }
        XCTAssertTrue(hasTerminal1)

        // Disable and invalidate
        UserDefaults.standard.set(false, forKey: key)
        HostAppRegistry.invalidateCache()

        let enabled2 = HostAppRegistry.enabledApps
        let hasTerminal2 = enabled2.contains { $0.id == "terminal" }
        XCTAssertFalse(hasTerminal2)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: key)
        HostAppRegistry.invalidateCache()
    }

    // MARK: - All Apps Registry

    func testAllAppsNotEmpty() {
        XCTAssertFalse(HostAppRegistry.allApps.isEmpty)
    }

    func testAllAppsHaveUniqueIds() {
        let ids = HostAppRegistry.allApps.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All app IDs should be unique")
    }

    func testAllAppsHaveProcessNames() {
        for app in HostAppRegistry.allApps {
            XCTAssertFalse(app.processNames.isEmpty,
                           "\(app.displayName) should have at least one process name")
        }
    }
}
