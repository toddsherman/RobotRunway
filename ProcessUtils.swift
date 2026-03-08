import Foundation

/// Lightweight wrapper for running shell commands and capturing output.
enum Shell {
    /// Run a command and return trimmed stdout.
    static func run(_ args: String...) -> String {
        run(args)
    }

    static func run(_ args: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return ""
        }
        // Read pipe BEFORE waitUntilExit to avoid deadlock when output fills the buffer
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Basic info about a running process, parsed from `ps`.
struct ProcessInfo {
    let pid: Int32
    let ppid: Int32
    let cpu: Double
    let command: String // full command line (args) for matching
}

/// Builds a snapshot of the process table.
enum ProcessTable {

    /// Parse `ps -eo pid,ppid,pcpu,args` into a lookup table.
    /// Uses `args` (not `comm`) to capture the full command line,
    /// which is needed to detect Node.js-based CLIs like Gemini.
    static func snapshot() -> [Int32: ProcessInfo] {
        let output = Shell.run("ps", "-eo", "pid,ppid,pcpu,args")
        var table: [Int32: ProcessInfo] = [:]

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]) else { continue }
            let command = String(parts[3])
            table[pid] = ProcessInfo(pid: pid, ppid: ppid, cpu: cpu, command: command)
        }

        return table
    }

    /// Find all descendants of a given PID (children, grandchildren, etc.)
    static func descendants(of pid: Int32, in table: [Int32: ProcessInfo]) -> [ProcessInfo] {
        var result: [ProcessInfo] = []
        var visited: Set<Int32> = [pid]
        var queue: [Int32] = [pid]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for (childPid, info) in table where info.ppid == current && !visited.contains(childPid) {
                visited.insert(childPid)
                result.append(info)
                queue.append(childPid)
            }
        }

        return result
    }

    /// Known AI coding assistant process names (matched against the executable basename).
    static let aiProcessNames: Set<String> = [
        "claude",                       // Anthropic Claude Code
        "codex",                        // OpenAI Codex
        "gemini",                       // Google Gemini CLI (Node.js script)
        "language_server_macos_arm",    // Google Antigravity (Gemini desktop)
    ]

    /// Extract the executable basename from a full `args` command string.
    /// For "node /opt/homebrew/bin/gemini ..." this returns "node".
    /// For "/usr/bin/claude --flag" this returns "claude".
    static func executableBasename(from args: String) -> String {
        guard let firstToken = args.split(separator: " ", maxSplits: 1).first else { return args }
        return (String(firstToken) as NSString).lastPathComponent
    }

    /// Check if a command args string references a known AI tool.
    /// Scans all space-separated tokens for known basenames. This handles:
    /// - Direct executables: `claude`, `/usr/local/bin/claude --flag`
    /// - Interpreter scripts: `node /opt/homebrew/bin/gemini`
    /// - Paths with spaces: `/Library/Application Support/.../claude`
    ///   (ps args output is unquoted, so the path splits into tokens
    ///    like `Support/.../claude` whose basename still matches)
    ///
    /// Excludes Electron helper processes (GPU, renderer, utility) which
    /// match AI names in their paths but are infrastructure, not AI workers.
    static func matchesAIProcess(_ args: String) -> Bool {
        // Skip Electron infrastructure processes — they match AI names in
        // their paths but are GPU/renderer/utility helpers, not AI workers.
        if args.contains("--type=gpu-process") ||
           args.contains("--type=renderer") ||
           args.contains("--type=utility") {
            return false
        }

        for token in args.split(separator: " ") {
            let baseName = (String(token) as NSString).lastPathComponent.lowercased()
            if aiProcessNames.contains(baseName) { return true }
        }
        return false
    }

    /// Find all PIDs whose command matches a known AI assistant.
    static func findAIProcesses(in table: [Int32: ProcessInfo]) -> [ProcessInfo] {
        table.values.filter { info in
            matchesAIProcess(info.command)
        }
    }
}
