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
    let command: String // full path or name
}

/// Builds a snapshot of the process table.
enum ProcessTable {

    /// Parse `ps -eo pid,ppid,pcpu,comm` into a lookup table.
    static func snapshot() -> [Int32: ProcessInfo] {
        let output = Shell.run("ps", "-eo", "pid,ppid,pcpu,comm")
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
        var queue: [Int32] = [pid]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for (childPid, info) in table where info.ppid == current && childPid != pid {
                result.append(info)
                queue.append(childPid)
            }
        }

        return result
    }

    /// Known AI coding assistant process names.
    static let aiProcessNames: Set<String> = [
        "claude",                       // Anthropic Claude Code
        "codex",                        // OpenAI Codex
        "language_server_macos_arm",    // Google Antigravity (Gemini)
    ]

    /// Find all PIDs whose command basename matches a known AI assistant.
    static func findAIProcesses(in table: [Int32: ProcessInfo]) -> [ProcessInfo] {
        table.values.filter { info in
            let baseName = (info.command as NSString).lastPathComponent
            return aiProcessNames.contains(baseName)
        }
    }
}
