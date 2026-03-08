import Foundation

/// Represents a terminal, IDE, or desktop app that can host AI coding sessions.
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
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: "hostApp.enabled.\(id)")
            HostAppRegistry.invalidateCache()
        }
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
            bundleIdentifier: "com.anthropic.claudefordesktop",
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
            processNames: ["Code Helper", "Code Helper (Renderer)"],
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
        HostApp(
            id: "codex-desktop",
            displayName: "Codex",
            processNames: ["Codex", "Codex Helper", "Codex Helper (Renderer)"],
            bundleIdentifier: "com.openai.codex",
            isElectron: true
        ),
        HostApp(
            id: "antigravity",
            displayName: "Antigravity",
            processNames: ["Antigravity Helper", "Antigravity Helper (Renderer)",
                           "Antigravity Helper (Plugin)"],
            bundleIdentifier: "com.google.antigravity",
            isElectron: true
        ),
    ]

    // MARK: - Enabled Apps Cache

    /// Cached set of enabled app IDs. Avoids 11 UserDefaults reads per poll cycle.
    private static var _enabledAppIds: Set<String>?

    /// Call when any app's enabled state changes to refresh the cache.
    static func invalidateCache() {
        _enabledAppIds = nil
    }

    private static var enabledAppIds: Set<String> {
        if let cached = _enabledAppIds { return cached }
        let ids = Set(allApps.filter {
            UserDefaults.standard.bool(forKey: "hostApp.enabled.\($0.id)")
        }.map(\.id))
        _enabledAppIds = ids
        return ids
    }

    /// Returns only the apps the user has enabled. Cached; invalidated on change.
    static var enabledApps: [HostApp] {
        let ids = enabledAppIds
        return allApps.filter { ids.contains($0.id) }
    }

    // MARK: - Host App Matching

    /// Find which host app a process belongs to by walking up the process tree.
    /// Returns the matched HostApp and the PID of the host app's process.
    ///
    /// Pre-computes lookup structures once per call for efficient matching:
    /// - Single-word names: O(1) dictionary lookup per token basename
    /// - Multi-word names: prefix/path-boundary matching
    static func hostApp(forProcessID pid: Int32, processTable: [Int32: ProcessInfo]) -> (app: HostApp, pid: Int32)? {
        let enabled = enabledApps

        // Pre-compute lookup structures once per call
        var singleWordLookup: [String: HostApp] = [:]
        var multiWordEntries: [(HostApp, [String])] = []

        for app in enabled {
            var multis: [String] = []
            for name in app.processNames {
                if name.contains(" ") {
                    multis.append(name)
                } else {
                    singleWordLookup[name] = app
                }
            }
            if !multis.isEmpty {
                multiWordEntries.append((app, multis))
            }
        }

        var current: Int32? = pid

        while let p = current, let info = processTable[p] {
            // Check single-word names via token basenames
            for token in info.command.split(separator: " ") {
                let basename = (String(token) as NSString).lastPathComponent
                if let app = singleWordLookup[basename] {
                    return (app, p)
                }
            }

            // Check multi-word names via path boundary matching
            for (app, names) in multiWordEntries {
                for name in names {
                    if info.command.hasPrefix(name) { return (app, p) }
                    if info.command.contains("/\(name)") { return (app, p) }
                }
            }

            current = info.ppid
            // Prevent infinite loop at pid 0/1
            if current == p || current == 0 { break }
        }

        return nil
    }

    /// Match a command string against known host app process names.
    /// Exposed as internal for testing.
    static func matchHostApp(command: String, in apps: [HostApp]) -> HostApp? {
        let tokenBasenames = command.split(separator: " ").map {
            (String($0) as NSString).lastPathComponent
        }

        for app in apps {
            for name in app.processNames {
                if name.contains(" ") {
                    if command.hasPrefix(name) { return app }
                    if command.contains("/\(name)") { return app }
                } else {
                    if tokenBasenames.contains(name) { return app }
                }
            }
        }
        return nil
    }
}
