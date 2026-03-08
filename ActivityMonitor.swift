import Foundation
import os

// MARK: - Running Statistics

/// Running statistics for a single signal using exponential moving averages.
/// O(1) memory, O(1) per update, trivially serializable.
struct SignalStats: Codable {
    var mean: Double = 0
    var variance: Double = 0
    var min: Double = .greatestFiniteMagnitude
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
    static let networkWeight: Double = 0.10
    static let cpuWeight: Double = 0.55
    static let childWeight: Double = 0.35

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

    static func sigmoid(_ x: Double) -> Double {
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

// MARK: - Activity Monitor

/// Orchestrates multi-signal monitoring of Claude Code sessions
/// with continuous adaptive learning.
class ActivityMonitor {

    var idleThresholdSeconds: TimeInterval = 120

    // NOTE: Single idleSince shared across all detected apps. This is intentional:
    // we only care about the "best" (most active) session for sleep management.
    // Per-app idle tracking would add complexity without clear UX benefit since
    // sleep is a system-wide concern.
    private var idleSince: Date?

    /// Rolling log of raw poll data (last 10 minutes).
    /// Access via currentPollLog() for thread-safe reads from other threads.
    private var pollLog: [PollLogEntry] = []
    private let pollLogMaxAge: TimeInterval = 600  // 10 minutes
    private let pollLogLock = NSLock()

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

    /// Thread-safe snapshot of the current poll log.
    /// Called from main thread by LogWindowController while poll runs on background queue.
    func currentPollLog() -> [PollLogEntry] {
        pollLogLock.lock()
        defer { pollLogLock.unlock() }
        return pollLog
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

        // Collect and classify ALL detected AI sessions
        struct ClassifiedSession {
            let snapshot: ActivitySnapshot
            let hostApp: HostApp
            let isActive: Bool
            let score: Double?
            let threshold: Double?
            let maturity: MaturityLevel
        }

        // Phase 1: Build process tree data, collect all PIDs needing network check
        struct SessionData {
            let aiProc: ProcessInfo
            let hostApp: HostApp
            let hostAppPid: Int32?
            let children: [ProcessInfo]
            let totalCPU: Double
            let networkPids: [Int32]
        }

        var sessionDataList: [SessionData] = []

        for aiProc in aiProcesses {
            let match = HostAppRegistry.hostApp(forProcessID: aiProc.pid, processTable: table)
            guard let hostApp = match?.app else { continue }
            let hostAppPid = match?.pid

            // Skip if the AI process IS the host app itself (e.g. main Electron process)
            if let hostPid = hostAppPid, aiProc.pid == hostPid { continue }

            let children = ProcessTable.descendants(of: aiProc.pid, in: table)
            let aiCPU = table[aiProc.pid]?.cpu ?? 0
            let totalCPU = children.reduce(aiCPU) { $0 + $1.cpu }

            // Collect PIDs for network check
            var networkPids: [Int32] = [aiProc.pid]
            if let hostPid = hostAppPid, hostPid != aiProc.pid,
               hostApp.isElectron {
                let hostChildren = ProcessTable.descendants(of: hostPid, in: table)
                let aiRelatedPids = hostChildren
                    .filter { ProcessTable.matchesAIProcess($0.command) }
                    .map(\.pid)
                if !aiRelatedPids.isEmpty {
                    networkPids.append(contentsOf: aiRelatedPids)
                    Log.monitor.debug("host tree check: hostPid=\(hostPid) aiPids=\(aiRelatedPids.count)")
                }
            }

            sessionDataList.append(SessionData(
                aiProc: aiProc, hostApp: hostApp, hostAppPid: hostAppPid,
                children: children, totalCPU: totalCPU, networkPids: networkPids
            ))
        }

        // Phase 2: Single batch lsof call for all PIDs
        let allNetworkPids = Array(Set(sessionDataList.flatMap(\.networkPids)))
        let connectionCounts = batchCountAPIConnections(pids: allNetworkPids)

        // Phase 3: Classify each session using batch results
        var sessions: [ClassifiedSession] = []

        for data in sessionDataList {
            let connections = data.networkPids.reduce(0) { $0 + (connectionCounts[$1] ?? 0) }

            Log.monitor.debug("sample: aiPid=\(data.aiProc.pid) cpu=\(data.totalCPU, format: .fixed(precision: 1)) net=\(connections) children=\(data.children.count)")

            let snapshot = ActivitySnapshot(
                aiPid: data.aiProc.pid,
                hostApp: data.hostApp,
                aggregateCPU: data.totalCPU,
                apiConnections: connections,
                childProcessCount: data.children.count,
                timestamp: Date()
            )

            var profile = profiles[data.hostApp.id] ?? ActivityProfile()
            let maturity = profile.maturityLevel
            let isActive: Bool
            var logScore: Double? = nil
            var logThreshold: Double? = nil

            if maturity == .coldStart {
                isActive = snapshot.isActiveByHeuristic
                Log.monitor.debug("classify \(data.hostApp.displayName, privacy: .public): heuristic=\(isActive) maturity=coldStart samples=\(profile.totalSamples)")
            } else {
                let (score, details) = snapshot.activityScore(profile: profile)
                isActive = score >= maturity.activityThreshold
                logScore = score
                logThreshold = maturity.activityThreshold
                Log.monitor.debug("classify \(data.hostApp.displayName, privacy: .public): score=\(score, format: .fixed(precision: 3)) threshold=\(maturity.activityThreshold) active=\(isActive) maturity=\(maturity.displayName, privacy: .public) cpu_s=\(details.cpu, format: .fixed(precision: 2)) child_s=\(details.children, format: .fixed(precision: 2))")
            }

            // Continuous learning for each app
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
            profiles[data.hostApp.id] = profile

            // Log entry for this app
            appendLogEntry(appName: data.hostApp.displayName, cpu: snapshot.aggregateCPU,
                           connections: snapshot.apiConnections,
                           childCount: snapshot.childProcessCount,
                           score: logScore, threshold: logThreshold,
                           isActive: isActive, maturity: maturity.displayName,
                           stateLabel: isActive ? "Active" : "Idle")

            sessions.append(ClassifiedSession(
                snapshot: snapshot, hostApp: data.hostApp, isActive: isActive,
                score: logScore, threshold: logThreshold, maturity: maturity
            ))
        }

        persistIfNeeded()

        guard let best = sessions.max(by: { a, b in
            if a.snapshot.apiConnections != b.snapshot.apiConnections {
                return a.snapshot.apiConnections < b.snapshot.apiConnections
            }
            return a.snapshot.aggregateCPU < b.snapshot.aggregateCPU
        }) else {
            idleSince = nil
            appendLogEntry(appName: nil, cpu: 0, connections: 0, childCount: 0,
                           score: nil, threshold: nil, isActive: false,
                           maturity: "—", stateLabel: "No Session")
            return .noSession
        }

        let appName = best.hostApp.displayName

        // State machine uses the most active session
        if best.isActive {
            idleSince = nil
            return .active(
                hostAppName: appName,
                cpu: best.snapshot.aggregateCPU,
                connections: best.snapshot.apiConnections,
                confidence: best.maturity
            )
        } else {
            let now = Date()
            if idleSince == nil { idleSince = now }
            let elapsed = now.timeIntervalSince(idleSince!)

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

        pollLogLock.lock()
        pollLog.append(entry)

        // Trim expired entries from front (entries are chronologically ordered)
        let cutoff = Date().addingTimeInterval(-pollLogMaxAge)
        if let firstValidIndex = pollLog.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValidIndex > 0 {
                pollLog.removeFirst(firstValidIndex)
            }
        } else {
            pollLog.removeAll()
        }
        pollLogLock.unlock()
    }

    // MARK: - Network Sampling (Batched)

    /// Batch lsof call: returns a dictionary mapping each PID to its ESTABLISHED connection count.
    /// Single call for all PIDs instead of one-per-process.
    private func batchCountAPIConnections(pids: [Int32]) -> [Int32: Int] {
        guard !pids.isEmpty else { return [:] }
        let pidList = pids.map(String.init).joined(separator: ",")
        let output = Shell.run(["lsof", "-i", "TCP:443", "-n", "-P", "-a", "-p", pidList], timeout: 10)

        var counts: [Int32: Int] = [:]
        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            guard lineStr.contains("ESTABLISHED") else { continue }
            // lsof output: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            let parts = lineStr.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            if parts.count >= 2, let pid = Int32(parts[1]) {
                counts[pid, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Profile Management

    func resetProfile(appId: String) {
        profiles.removeValue(forKey: appId)
        saveProfiles()
    }

    func resetAllProfiles() {
        profiles.removeAll()
        saveProfiles()
        Log.profile.notice("All learned profiles reset")
    }

    // MARK: - Persistence

    func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: "activityProfiles")
            Log.profile.debug("Saved \(self.profiles.count) profile(s)")
        } catch {
            Log.profile.error("Failed to encode profiles: \(error.localizedDescription)")
        }
        lastPersistTime = Date()
    }

    private func persistIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPersistTime) >= persistInterval else { return }
        saveProfiles()
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: "activityProfiles") else { return }
        do {
            profiles = try JSONDecoder().decode([String: ActivityProfile].self, from: data)
            Log.profile.info("Loaded \(self.profiles.count) profile(s)")
        } catch {
            Log.profile.error("Failed to decode profiles: \(error.localizedDescription)")
        }
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
        Log.profile.notice("Migrated \(oldBaselines.count) legacy baseline(s) to activity profiles")
    }
}
