import XCTest

class SignalStatsTests: XCTestCase {

    func testInitialState() {
        let stats = SignalStats()
        XCTAssertEqual(stats.mean, 0)
        XCTAssertEqual(stats.variance, 0)
        XCTAssertEqual(stats.min, .greatestFiniteMagnitude)
        XCTAssertEqual(stats.max, 0)
        XCTAssertEqual(stats.sampleCount, 0)
        XCTAssertEqual(stats.stdDev, 0)
    }

    func testFirstUpdateSetsDirectly() {
        var stats = SignalStats()
        stats.update(value: 42.0, alpha: 0.3)

        XCTAssertEqual(stats.sampleCount, 1)
        XCTAssertEqual(stats.mean, 42.0)
        XCTAssertEqual(stats.variance, 0)
        XCTAssertEqual(stats.min, 42.0)
        XCTAssertEqual(stats.max, 42.0)
    }

    func testEMAConvergenceWithConstantInput() {
        var stats = SignalStats()
        let constant = 10.0
        let alpha = 0.3

        for _ in 0..<100 {
            stats.update(value: constant, alpha: alpha)
        }

        XCTAssertEqual(stats.mean, constant, accuracy: 0.001,
                       "Mean should converge to constant input")
        XCTAssertEqual(stats.min, constant)
        XCTAssertEqual(stats.max, constant)
    }

    func testEMATracksChangingValues() {
        var stats = SignalStats()
        let alpha = 0.3

        // First 50 at value 10
        for _ in 0..<50 {
            stats.update(value: 10.0, alpha: alpha)
        }
        XCTAssertEqual(stats.mean, 10.0, accuracy: 0.01)

        // Next 200 at value 50 — should converge toward 50
        for _ in 0..<200 {
            stats.update(value: 50.0, alpha: alpha)
        }
        XCTAssertEqual(stats.mean, 50.0, accuracy: 0.01,
                       "Mean should converge to new constant after enough samples")
    }

    func testHigherAlphaTracksFaster() {
        var slowStats = SignalStats()
        var fastStats = SignalStats()

        // Initialize both at 0
        slowStats.update(value: 0, alpha: 0.02)
        fastStats.update(value: 0, alpha: 0.3)

        // Push toward 100
        for _ in 0..<10 {
            slowStats.update(value: 100.0, alpha: 0.02)
            fastStats.update(value: 100.0, alpha: 0.3)
        }

        XCTAssertGreaterThan(fastStats.mean, slowStats.mean,
                             "Higher alpha should track changes faster")
    }

    func testMinMaxTracking() {
        var stats = SignalStats()
        let values: [Double] = [5, 2, 8, 1, 9, 3]

        for v in values {
            stats.update(value: v, alpha: 0.3)
        }

        XCTAssertEqual(stats.min, 1.0)
        XCTAssertEqual(stats.max, 9.0)
    }

    func testVarianceIsNonNegative() {
        var stats = SignalStats()
        let values: [Double] = [10, 20, 5, 50, 2, 100]

        for v in values {
            stats.update(value: v, alpha: 0.3)
        }

        XCTAssertGreaterThanOrEqual(stats.variance, 0)
    }

    func testStdDevIsSquareRootOfVariance() {
        var stats = SignalStats()

        for v in [10.0, 20.0, 30.0, 40.0, 50.0] {
            stats.update(value: v, alpha: 0.3)
        }

        XCTAssertEqual(stats.stdDev, sqrt(stats.variance), accuracy: 1e-10)
    }

    func testVarianceWithIdenticalValues() {
        var stats = SignalStats()

        for _ in 0..<50 {
            stats.update(value: 7.0, alpha: 0.3)
        }

        XCTAssertEqual(stats.variance, 0, accuracy: 1e-10,
                       "Variance should be ~0 for identical values")
    }

    func testSampleCountIncrements() {
        var stats = SignalStats()

        for i in 1...10 {
            stats.update(value: Double(i), alpha: 0.3)
            XCTAssertEqual(stats.sampleCount, i)
        }
    }
}
