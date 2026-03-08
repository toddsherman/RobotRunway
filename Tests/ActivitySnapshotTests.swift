import XCTest

class ActivitySnapshotTests: XCTestCase {

    // MARK: - Heuristic (Cold Start)

    func testHeuristicActiveHighCPU() {
        let snap = makeSnapshot(cpu: 10.0, connections: 0, children: 0)
        XCTAssertTrue(snap.isActiveByHeuristic,
                      "CPU > 5.0 should be active by heuristic")
    }

    func testHeuristicActiveManyChildren() {
        let snap = makeSnapshot(cpu: 0.0, connections: 0, children: 3)
        XCTAssertTrue(snap.isActiveByHeuristic,
                      "childProcessCount > 2 should be active by heuristic")
    }

    func testHeuristicInactiveLowSignals() {
        let snap = makeSnapshot(cpu: 3.0, connections: 5, children: 1)
        XCTAssertFalse(snap.isActiveByHeuristic,
                       "Low CPU and few children should be inactive (network ignored in heuristic)")
    }

    func testHeuristicBoundaryValues() {
        // Exactly at thresholds — should be inactive (> not >=)
        let atCPU = makeSnapshot(cpu: 5.0, connections: 0, children: 0)
        XCTAssertFalse(atCPU.isActiveByHeuristic, "CPU == 5.0 should NOT be active")

        let atChildren = makeSnapshot(cpu: 0.0, connections: 0, children: 2)
        XCTAssertFalse(atChildren.isActiveByHeuristic, "children == 2 should NOT be active")
    }

    // MARK: - Signal Weights

    func testWeightsSumToOne() {
        let total = ActivitySnapshot.networkWeight + ActivitySnapshot.cpuWeight + ActivitySnapshot.childWeight
        XCTAssertEqual(total, 1.0, accuracy: 1e-10,
                       "Signal weights should sum to 1.0")
    }

    func testCPUWeightIsDominant() {
        XCTAssertGreaterThan(ActivitySnapshot.cpuWeight, ActivitySnapshot.childWeight)
        XCTAssertGreaterThan(ActivitySnapshot.cpuWeight, ActivitySnapshot.networkWeight)
    }

    // MARK: - Activity Score

    func testNetworkScoreBinary() {
        let profile = makeProfile()

        let noNet = makeSnapshot(cpu: 0, connections: 0, children: 0)
        let (_, noNetDetails) = noNet.activityScore(profile: profile)
        XCTAssertEqual(noNetDetails.network, 0.0)

        let withNet = makeSnapshot(cpu: 0, connections: 1, children: 0)
        let (_, withNetDetails) = withNet.activityScore(profile: profile)
        XCTAssertEqual(withNetDetails.network, 1.0)

        let multiNet = makeSnapshot(cpu: 0, connections: 10, children: 0)
        let (_, multiNetDetails) = multiNet.activityScore(profile: profile)
        XCTAssertEqual(multiNetDetails.network, 1.0, "Multiple connections still = 1.0")
    }

    func testHighCPUGivesHighScore() {
        var profile = makeProfile()
        // Idle CPU baseline: mean=2.0, stdDev=1.0
        profile.idleCPU = SignalStats(mean: 2.0, variance: 1.0, min: 0, max: 5, sampleCount: 100)

        let highCPU = makeSnapshot(cpu: 50.0, connections: 0, children: 0)
        let (score, details) = highCPU.activityScore(profile: profile)

        XCTAssertGreaterThan(details.cpu, 0.9,
                             "CPU score should be high when far above idle mean")
        XCTAssertGreaterThan(score, 0.4)
    }

    func testIdleCPUGivesLowScore() {
        var profile = makeProfile()
        profile.idleCPU = SignalStats(mean: 2.0, variance: 1.0, min: 0, max: 5, sampleCount: 100)

        let lowCPU = makeSnapshot(cpu: 2.0, connections: 0, children: 0)
        let (score, details) = lowCPU.activityScore(profile: profile)

        XCTAssertLessThan(details.cpu, 0.2,
                          "CPU score should be low when at idle mean")
        XCTAssertLessThan(score, 0.3)
    }

    func testScoreInUnitRange() {
        let profile = makeProfile()
        let testCases: [(Double, Int, Int)] = [
            (0, 0, 0), (100, 10, 20), (0, 0, 50), (50, 5, 5),
        ]

        for (cpu, conn, children) in testCases {
            let snap = makeSnapshot(cpu: cpu, connections: conn, children: children)
            let (score, _) = snap.activityScore(profile: profile)
            XCTAssertGreaterThanOrEqual(score, 0.0,
                                        "Score should be >= 0 for cpu=\(cpu)")
            XCTAssertLessThanOrEqual(score, 1.0,
                                     "Score should be <= 1 for cpu=\(cpu)")
        }
    }

    // MARK: - Sigmoid

    func testSigmoidAtZero() {
        XCTAssertEqual(ActivitySnapshot.sigmoid(0), 0.5, accuracy: 1e-10)
    }

    func testSigmoidLargePositive() {
        XCTAssertGreaterThan(ActivitySnapshot.sigmoid(10), 0.999)
    }

    func testSigmoidLargeNegative() {
        XCTAssertLessThan(ActivitySnapshot.sigmoid(-10), 0.001)
    }

    func testSigmoidSymmetry() {
        for x in [0.5, 1.0, 2.0, 5.0] {
            let sum = ActivitySnapshot.sigmoid(x) + ActivitySnapshot.sigmoid(-x)
            XCTAssertEqual(sum, 1.0, accuracy: 1e-10,
                           "sigmoid(x) + sigmoid(-x) should equal 1")
        }
    }

    // MARK: - Helpers

    private func makeSnapshot(cpu: Double, connections: Int, children: Int) -> ActivitySnapshot {
        ActivitySnapshot(
            aiPid: 1234,
            hostApp: nil,
            aggregateCPU: cpu,
            apiConnections: connections,
            childProcessCount: children,
            timestamp: Date()
        )
    }

    private func makeProfile() -> ActivityProfile {
        var p = ActivityProfile()
        p.totalSamples = 100
        p.idleCPU = SignalStats(mean: 2.0, variance: 4.0, min: 0, max: 10, sampleCount: 50)
        p.idleChildren = SignalStats(mean: 1.0, variance: 0.25, min: 0, max: 3, sampleCount: 50)
        return p
    }
}
