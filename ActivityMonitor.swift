import Foundation

// MARK: - Running Statistics

/// Running statistics for a single signal using exponential moving averages.
/// O(1) memory, O(1) per update, trivially serializable.
struct SignalStats: Codable {
    var mean: Double = 0
    var variance: Double = 0
    var min: Double = .infinity
    var max: Double = 0
    var sampleCount: Int = 0

    /// Update with a new observation using exponential moving average.
    mutating func update(value: Double, alpha: Double) {
        sampleCount += 1
        if sampleCount == 1 {
            mean = value
            variance = 0
            min = value
            max = value
            return
        }
        let diff = value - mean
        mean += alpha * diff
        // Welford-like online variance with EMA weighting
        variance = (1 - alpha) * (variance + alpha * diff * diff)
        if value < min { min = value }
        if value > max { max = value }
    }

    var stdDev: Double { sqrt(Swift.max(variance, 0)) }
}

// MARK: - Maturity Level

/// How mature a profile is, based on cumulative sample count.
enum MaturityLevel: Int, Codable, Comparable {
    case coldStart = 0    // < 6 samples (~30s of Claude usage)
    case learning = 1     // 6-59 samples (~30s to 5min)
    case developing = 2   // 60-359 samples (~5min to 30min)
    case mature = 3       // 360+ samples (~30min+)

    static func < (lhs: MaturityLevel, rhs: MaturityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .coldStart:  return "Starting"
        case .learning:   return "Learning"
        case .developing: return "Developing"
        case .mature:     return "Mature"
        }
    }

    /// EMA learning rate — decreases as profile matures for stability.
    var alpha: Double {
        switch self {
        case .coldStart:  return 0.3
        case .learning:   return 0.15
        case .developing: return 0.05
        case .mature:     return 0.02
        }
    }

    /// Activity score threshold — starts cautious, tightens with confidence.
    var activityThreshold: Double {
        switch self {
        case .coldStart:  return 0.15
        case .learning:   return 0.25
        case .developing: return 0.35
        case .mature:     return 0.40
        }
    }
}

// MARK: - Activity Profile

/// Learned activity profile for a host app. Tracks separate idle and active
/// distributions for each signal, continuously refined over time.
struct ActivityProfile: Codable {
    // Idle distributions (one per signal)
    var idleCPU = SignalStats()
    var idleNetwork = SignalStats()
    var idleChildren = SignalStats()

    // Active distributions (one per signal)
    var activeCPU = SignalStats()
    var activeNetwork = SignalStats()
    var activeChildren = SignalStats()

    // Metadata
    var totalSamples: Int = 0
    var idleSamples: Int = 0
    var activeSamples: Int = 0
    var createdAt: Date = Date()
    var lastUpdatedAt: Date = Date()

    var version: Int = 1

    var maturityLevel: MaturityLevel {
        if totalSamples < 6 { return .coldStart }
        if totalSamples < 60 { return .learning }
        if totalSamples < 360 { return .developing }
        return .mature
    }
}

// MARK: - Signal Scores

/// Per-signal contribution to the overall activity score.
struct SignalScores {
    let network: Double
    let cpu: Double
    let children: Double
}

// MARK: - Activity Snapshot

/// A snapshot of activity signals for an AI coding session.
struct ActivitySnapshot {
    let aiPid: Int32
    let hostApp: HostApp?
    /// Aggregate CPU% of the AI process + all its children.
    let aggregateCPU: Double
    /// Number of established TCP connections to API endpoints (port 443).
    let apiConnections: Int
    /// Number of child processes under the AI process.
    let childProcessCount: Int
    let timestamp: Date

    // Signal weights — CPU is primary since HTTP/2 keeps connections
    // open even when idle; network is a presence indicator only.
    private static let networkWeight: Double = 0.10
    private static let cpuWeight: Double = 0.55
    private static let childWeight: Double = 0.35

    /// Compute a weighted activity score in [0, 1] using the learned profile.
    func activityScore(profile: ActivityProfile) -> (score: Double, details: SignalScores) {
        // Network: binary — any API connection = definitely active
        let networkScore: Double = apiConnections > 0 ? 1.0 : 0.0

        // CPU: sigmoid of z-score relative to idle distribution
        let idleCPUStdDev = Swift.max(profile.idleCPU.stdDev, 1.0)
        let cpuZScore = (aggregateCPU - profile.idleCPU.mean) / idleCPUStdDev
        let cpuScore = ActivitySnapshot.sigmoid(cpuZScore - 2.0)

        // Children: sigmoid of z-score relative to idle distribution
        let idleChildStdDev = Swift.max(profile.idleChildren.stdDev, 0.5)
        let childZScore = (Double(childProcessCount) - profile.idleChildren.mean) / idleChildStdDev
        let childScore = ActivitySnapshot.sigmoid(childZScore - 1.5)

        let score = Self.networkWeight * networkScore
                  + Self.cpuWeight * cpuScore
                  + Self.childWeight * childScore

        return (score, SignalScores(network: networkScore, cpu: cpuScore, children: childScore))
    }

    /// Bootstrap heuristic for cold-start classification (no learned data yet).
    /// Network excluded: HTTP/2 keeps connections open even when idle.
    var isActiveByHeuristic: Bool {
        aggregateCPU > 5.0 || childProcessCount > 2
    }

    private static func sigmoid(_ x: Double) -> Double {
        1.0 / (1.0 + exp(-x))
    }
}

// MARK: - Monitor State

/// Represents the overall state of Claude Code monitoring.
enum MonitorState: Equatable {
    case noSession
    case active(hostAppName: String, cpu: Double, connections: Int, confidence: MaturityLevel)
    case idleCooldown(hostAppName: String, elapsed: TimeInterval, threshold: TimeInterval)
    case idle(hostAppName: String, idleDuration: TimeInterval)
    case paused
}

// MARK: - Poll Log Entry

struct PollLogEntry {
    let timestamp: Date
    let appName: String?
    let cpu: Double
    let connections: Int
    let childCount: Int
    let score: Double?       // nil during cold start
    let threshold: Double?   // nil during cold start
    let isActive: Bool
    let maturity: String
    let stateLabel: String   // "Active", "Idle Cooldown", "Idle", "No Session"
}

// MARK: - Legacy Baseline (for migration only)

struct LegacyBaseline: Codable {
    var cpu: Double = 2.0
    var cpuMargin: Double = 5.0
    var networkConnections: Int = 0
    var childCount: Int = 0
    var sampleCount: Int = 0
    var isComplete: Bool = false
}

// MARK: - Debug Logging

private let _logPath = (NSHomeDirectory() as NSString).appendingPathComponent("robotrunway-debug.log")
private let _logDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss.SSS"
    return df
}()
func caLog(_ message: String) {
    let line = "\(_logDateFormatter.string(from: Date())) \(message)\n"
    if let handle = FileHandle(forWritingAtPath: _logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: _logPath, contents: line.data(using: .utf8))
    }
}

// MARK: - Activity Monitor

/// Orchestrates multi-signal monitoring of Claude Code sessions
/// with continuous adaptive learning.
class ActivityMonitor {

    var idleThresholdSeconds: TimeInterval = 120

    private var idleSince: Date?

    /// Rolling log of raw poll data (last 10 minutes).
    private(set) var pollLog: [PollLogEntry] = []
    private let pollLogMaxAge: TimeInterval = 600  // 10 minutes

    /// Per-host-app learned profiles.
    private(set) var profiles: [String: ActivityProfile] = [:]

    /// Throttled persistence.
    private var lastPersistTime: Date = .distantPast
    private let persistInterval: TimeInterval = 30

    init() {
        migrateFromLegacyBaselinesIfNeeded()
        loadProfiles()
    }

    /// Get the profile for a specific app.
    func profile(forAppId appId: String) -> ActivityProfile? {
        profiles[appId]
    }

    // MARK: - Main Poll

    func poll() -> MonitorState {
        let table = ProcessTable.snapshot()
        let aiProcesses = ProcessTable.findAIProcesses(in: table)

        guard !aiProcesses.isEmpty else {
            idleSince = nil
            appendLogEntry(appName: nil, cpu: 0, connections: 0, childCount: 0,
                           score: nil, threshold: nil, isActive: false,
                           maturity: "—", stateLabel: "No Session")
            return .noSession
        }

        // Find the most active AI session
        var bestSnapshot: ActivitySnapshot?
        var bestHostApp: HostApp?

        for aiProc in aiProcesses {
            let match = HostAppRegistry.hostApp(forProcessID: aiProc.pid, processTable: table)
            // Only monitor AI processes running inside enabled host apps
            guard let hostApp = match?.app else { continue }
            let hostAppPid = match?.pid
            let snapshot = sampleSession(aiPid: aiProc.pid, hostApp: hostApp, hostAppPid: hostAppPid, table: table)

            if let existing = bestSnapshot {
                if snapshot.apiConnections > existing.apiConnections ||
                   snapshot.aggregateCPU > existing.aggregateCPU {
                    bestSnapshot = snapshot
                    bestHostApp = hostApp
                }
            } else {
                bestSnapshot = snapshot
                bestHostApp = hostApp
            }
        }

        guard let snapshot = bestSnapshot else {
            idleSince = nil
            appendLogEntry(appName: nil, cpu: 0, connections: 0, childCount: 0,
                           score: nil, threshold: nil, isActive: false,
                           maturity: "—", stateLabel: "No Session")
            return .noSession
        }

        let appId = bestHostApp!.id
        let appName = bestHostApp!.displayName
        var profile = profiles[appId] ?? ActivityProfile()

        // Classify this sample
        let isActive: Bool
        let maturity = profile.maturityLevel
        var logScore: Double? = nil
        var logThreshold: Double? = nil

        if maturity == .coldStart {
            isActive = snapshot.isActiveByHeuristic
            caLog("  classify: heuristic=\(isActive) maturity=coldStart samples=\(profile.totalSamples)")
        } else {
            let (score, details) = snapshot.activityScore(profile: profile)
            isActive = score >= maturity.activityThreshold
            logScore = score
            logThreshold = maturity.activityThreshold
            caLog("  classify: score=\(String(format:"%.3f", score)) threshold=\(maturity.activityThreshold) active=\(isActive) maturity=\(maturity.displayName) cpu_s=\(String(format:"%.2f", details.cpu)) child_s=\(String(format:"%.2f", details.children))")
        }

        // Continuous learning: update the appropriate distribution
        let a = maturity.alpha
        if isActive {
            profile.activeCPU.update(value: snapshot.aggregateCPU, alpha: a)
            profile.activeNetwork.update(value: Double(snapshot.apiConnections), alpha: a)
            profile.activeChildren.update(value: Double(snapshot.childProcessCount), alpha: a)
            profile.activeSamples += 1
        } else {
            profile.idleCPU.update(value: snapshot.aggregateCPU, alpha: a)
            profile.idleNetwork.update(value: Double(snapshot.apiConnections), alpha: a)
            profile.idleChildren.update(value: Double(snapshot.childProcessCount), alpha: a)
            profile.idleSamples += 1
        }
        profile.totalSamples += 1
        profile.lastUpdatedAt = Date()

        profiles[appId] = profile
        persistIfNeeded()

        // State machine
        if isActive {
            idleSince = nil
            appendLogEntry(appName: appName, cpu: snapshot.aggregateCPU,
                           connections: snapshot.apiConnections,
                           childCount: snapshot.childProcessCount,
                           score: logScore, threshold: logThreshold,
                           isActive: true, maturity: maturity.displayName,
                           stateLabel: "Active")
            return .active(
                hostAppName: appName,
                cpu: snapshot.aggregateCPU,
                connections: snapshot.apiConnections,
                confidence: profile.maturityLevel
            )
        } else {
            let now = Date()
            if idleSince == nil { idleSince = now }
            let elapsed = now.timeIntervalSince(idleSince!)

            let stateLabel = elapsed >= idleThresholdSeconds ? "Idle" : "Idle Cooldown"
            appendLogEntry(appName: appName, cpu: snapshot.aggregateCPU,
                           connections: snapshot.apiConnections,
                           childCount: snapshot.childProcessCount,
                           score: logScore, threshold: logThreshold,
                           isActive: false, maturity: maturity.displayName,
                           stateLabel: stateLabel)

            if elapsed >= idleThresholdSeconds {
                return .idle(hostAppName: appName, idleDuration: elapsed)
            } else {
                return .idleCooldown(
                    hostAppName: appName,
                    elapsed: elapsed,
                    threshold: idleThresholdSeconds
                )
            }
        }
    }

    // MARK: - Poll Log

    private func appendLogEntry(appName: String?, cpu: Double, connections: Int,
                                childCount: Int, score: Double?, threshold: Double?,
                                isActive: Bool, maturity: String, stateLabel: String) {
        let entry = PollLogEntry(
            timestamp: Date(), appName: appName, cpu: cpu,
            connections: connections, childCount: childCount,
            score: score, threshold: threshold, isActive: isActive,
            maturity: maturity, stateLabel: stateLabel
        )
        pollLog.append(entry)

        // Trim entries older than 10 minutes
        let cutoff = Date().addingTimeInterval(-pollLogMaxAge)
        pollLog.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Signal Sampling

    private func sampleSession(aiPid: Int32, hostApp: HostApp?, hostAppPid: Int32?, table: [Int32: ProcessInfo]) -> ActivitySnapshot {
        let children = ProcessTable.descendants(of: aiPid, in: table)
        let aiCPU = table[aiPid]?.cpu ?? 0
        let totalCPU = children.reduce(aiCPU) { $0 + $1.cpu }

        // Check AI process for API connections
        var connections = countAPIConnections(pids: [aiPid])

        // For Electron host apps, also check AI-related processes in the
        // host tree — but only processes matching known AI names, not the
        // entire tree (which would count unrelated HTTPS traffic).
        if connections == 0, let hostPid = hostAppPid, hostPid != aiPid,
           hostApp?.isElectron == true {
            let hostChildren = ProcessTable.descendants(of: hostPid, in: table)
            let aiRelatedPids = hostChildren
                .filter { ProcessTable.matchesAIProcess($0.command) }
                .map(\.pid)
            if !aiRelatedPids.isEmpty {
                connections = countAPIConnections(pids: aiRelatedPids)
                caLog("  host tree check: hostPid=\(hostPid) aiPids=\(aiRelatedPids.count) connections=\(connections)")
            }
        }

        caLog("  sample: aiPid=\(aiPid) cpu=\(String(format:"%.1f", totalCPU)) net=\(connections) children=\(children.count)")

        return ActivitySnapshot(
            aiPid: aiPid,
            hostApp: hostApp,
            aggregateCPU: totalCPU,
            apiConnections: connections,
            childProcessCount: children.count,
            timestamp: Date()
        )
    }

    /// Count ESTABLISHED TCP connections to port 443 for the given PIDs.
    /// AI CLI tools only connect to their vendor's API over HTTPS, so any
    /// port-443 connection is an API connection. This avoids fragile IP matching.
    private func countAPIConnections(pids: [Int32]) -> Int {
        let pidList = pids.map(String.init).joined(separator: ",")
        let output = Shell.run("lsof", "-i", "TCP:443", "-n", "-P", "-a", "-p", pidList)
        var count = 0

        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            if lineStr.contains("ESTABLISHED") {
                count += 1
            }
        }
        return count
    }

    // MARK: - Profile Management

    func resetProfile(appId: String) {
        profiles.removeValue(forKey: appId)
        saveProfiles()
    }

    func resetAllProfiles() {
        profiles.removeAll()
        saveProfiles()
        NSLog("[RobotRunway] All learned profiles reset")
    }

    // MARK: - Persistence

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "activityProfiles")
        }
        lastPersistTime = Date()
    }

    private func persistIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPersistTime) >= persistInterval else { return }
        saveProfiles()
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: "activityProfiles"),
              let decoded = try? JSONDecoder().decode([String: ActivityProfile].self, from: data) else { return }
        profiles = decoded
    }

    // MARK: - Migration

    private func migrateFromLegacyBaselinesIfNeeded() {
        guard let oldData = UserDefaults.standard.data(forKey: "calibrationBaselines"),
              UserDefaults.standard.data(forKey: "activityProfiles") == nil,
              let oldBaselines = try? JSONDecoder().decode([String: LegacyBaseline].self, from: oldData)
        else { return }

        for (appId, old) in oldBaselines where old.isComplete {
            var profile = ActivityProfile()
            profile.idleCPU = SignalStats(
                mean: old.cpu,
                variance: pow(old.cpuMargin / 3.0, 2),
                min: old.cpu, max: old.cpu,
                sampleCount: old.sampleCount
            )
            profile.idleNetwork = SignalStats(
                mean: Double(old.networkConnections),
                variance: 0, min: Double(old.networkConnections),
                max: Double(old.networkConnections),
                sampleCount: old.sampleCount
            )
            profile.idleChildren = SignalStats(
                mean: Double(old.childCount),
                variance: 0.25, min: Double(old.childCount),
                max: Double(old.childCount),
                sampleCount: old.sampleCount
            )
            profile.totalSamples = old.sampleCount
            profile.idleSamples = old.sampleCount
            profiles[appId] = profile
        }

        saveProfiles()
        UserDefaults.standard.removeObject(forKey: "calibrationBaselines")
        NSLog("[RobotRunway] Migrated %d legacy baseline(s) to activity profiles", oldBaselines.count)
    }
}
