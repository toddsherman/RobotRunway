import Foundation

/// Represents a terminal or IDE application that can host Claude Code sessions.
struct HostApp: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    /// Process names to match against (the executable basename, not the full path).
    /// Multiple entries handle variants (e.g., VS Code has "Code Helper", "Electron", etc.)
    let processNames: [String]
    /// Bundle identifier for locating the app and its icon
    let bundleIdentifier: String?
    /// Whether this app uses an Electron-based process tree (deeper nesting)
    let isElectron: Bool

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "hostApp.enabled.\(id)") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "hostApp.enabled.\(id)") }
    }

}

/// Registry of all supported host applications.
enum HostAppRegistry {

    static let allApps: [HostApp] = [
        HostApp(
            id: "terminal",
            displayName: "Terminal",
            processNames: ["Terminal"],
            bundleIdentifier: "com.apple.Terminal",
            isElectron: false
        ),
        HostApp(
            id: "iterm2",
            displayName: "iTerm2",
            processNames: ["iTerm2"],
            bundleIdentifier: "com.googlecode.iterm2",
            isElectron: false
        ),
        HostApp(
            id: "claude-desktop",
            displayName: "Claude Desktop",
            processNames: ["Claude"],
            bundleIdentifier: "com.anthropic.claude",
            isElectron: true
        ),
        HostApp(
            id: "warp",
            displayName: "Warp",
            processNames: ["Warp", "WarpTerminal"],
            bundleIdentifier: "dev.warp.Warp-Stable",
            isElectron: false
        ),
        HostApp(
            id: "vscode",
            displayName: "VS Code",
            processNames: ["Electron", "Code Helper", "Code Helper (Renderer)"],
            bundleIdentifier: "com.microsoft.VSCode",
            isElectron: true
        ),
        HostApp(
            id: "cursor",
            displayName: "Cursor",
            processNames: ["Cursor", "Cursor Helper", "Cursor Helper (Renderer)"],
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            isElectron: true
        ),
        HostApp(
            id: "kitty",
            displayName: "Kitty",
            processNames: ["kitty"],
            bundleIdentifier: "net.kovidgoyal.kitty",
            isElectron: false
        ),
        HostApp(
            id: "alacritty",
            displayName: "Alacritty",
            processNames: ["alacritty"],
            bundleIdentifier: "org.alacritty",
            isElectron: false
        ),
        HostApp(
            id: "hyper",
            displayName: "Hyper",
            processNames: ["Hyper", "Hyper Helper"],
            bundleIdentifier: "co.zeit.hyper",
            isElectron: true
        ),
    ]

    /// Returns only the apps the user has enabled.
    static var enabledApps: [HostApp] {
        allApps.filter(\.isEnabled)
    }

    /// Find which host app a process belongs to by walking up the process tree.
    static func hostApp(forProcessID pid: Int32, processTable: [Int32: ProcessInfo]) -> HostApp? {
        let enabledNames = Set(enabledApps.flatMap(\.processNames))
        var current: Int32? = pid

        while let p = current, let info = processTable[p] {
            let baseName = (info.command as NSString).lastPathComponent
            if enabledNames.contains(baseName) {
                return enabledApps.first { $0.processNames.contains(baseName) }
            }
            current = info.ppid
            // Prevent infinite loop at pid 0/1
            if current == p || current == 0 { break }
        }

        return nil
    }
}
