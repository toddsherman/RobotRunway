import XCTest

class MaturityLevelTests: XCTestCase {

    // MARK: - Threshold Boundaries

    func testColdStartRange() {
        for count in [0, 1, 3, 5] {
            var profile = ActivityProfile()
            profile.totalSamples = count
            XCTAssertEqual(profile.maturityLevel, .coldStart,
                           "totalSamples=\(count) should be coldStart")
        }
    }

    func testLearningRange() {
        for count in [6, 10, 30, 59] {
            var profile = ActivityProfile()
            profile.totalSamples = count
            XCTAssertEqual(profile.maturityLevel, .learning,
                           "totalSamples=\(count) should be learning")
        }
    }

    func testDevelopingRange() {
        for count in [60, 100, 200, 359] {
            var profile = ActivityProfile()
            profile.totalSamples = count
            XCTAssertEqual(profile.maturityLevel, .developing,
                           "totalSamples=\(count) should be developing")
        }
    }

    func testMatureRange() {
        for count in [360, 500, 1000, 10000] {
            var profile = ActivityProfile()
            profile.totalSamples = count
            XCTAssertEqual(profile.maturityLevel, .mature,
                           "totalSamples=\(count) should be mature")
        }
    }

    // MARK: - Exact Boundary Values

    func testExactBoundaries() {
        var p5 = ActivityProfile(); p5.totalSamples = 5
        XCTAssertEqual(p5.maturityLevel, .coldStart)

        var p6 = ActivityProfile(); p6.totalSamples = 6
        XCTAssertEqual(p6.maturityLevel, .learning)

        var p59 = ActivityProfile(); p59.totalSamples = 59
        XCTAssertEqual(p59.maturityLevel, .learning)

        var p60 = ActivityProfile(); p60.totalSamples = 60
        XCTAssertEqual(p60.maturityLevel, .developing)

        var p359 = ActivityProfile(); p359.totalSamples = 359
        XCTAssertEqual(p359.maturityLevel, .developing)

        var p360 = ActivityProfile(); p360.totalSamples = 360
        XCTAssertEqual(p360.maturityLevel, .mature)
    }

    // MARK: - Alpha Values

    func testAlphaValues() {
        XCTAssertEqual(MaturityLevel.coldStart.alpha, 0.3)
        XCTAssertEqual(MaturityLevel.learning.alpha, 0.15)
        XCTAssertEqual(MaturityLevel.developing.alpha, 0.05)
        XCTAssertEqual(MaturityLevel.mature.alpha, 0.02)
    }

    func testAlphaDecreaseWithMaturity() {
        let levels: [MaturityLevel] = [.coldStart, .learning, .developing, .mature]
        for i in 1..<levels.count {
            XCTAssertLessThan(levels[i].alpha, levels[i-1].alpha,
                              "\(levels[i]) alpha should be less than \(levels[i-1]) alpha")
        }
    }

    // MARK: - Activity Thresholds

    func testActivityThresholdValues() {
        XCTAssertEqual(MaturityLevel.coldStart.activityThreshold, 0.15)
        XCTAssertEqual(MaturityLevel.learning.activityThreshold, 0.25)
        XCTAssertEqual(MaturityLevel.developing.activityThreshold, 0.35)
        XCTAssertEqual(MaturityLevel.mature.activityThreshold, 0.40)
    }

    func testThresholdIncreasesWithMaturity() {
        let levels: [MaturityLevel] = [.coldStart, .learning, .developing, .mature]
        for i in 1..<levels.count {
            XCTAssertGreaterThan(levels[i].activityThreshold, levels[i-1].activityThreshold,
                                 "\(levels[i]) threshold should be higher than \(levels[i-1])")
        }
    }

    // MARK: - Comparable

    func testComparable() {
        XCTAssertLessThan(MaturityLevel.coldStart, .learning)
        XCTAssertLessThan(MaturityLevel.learning, .developing)
        XCTAssertLessThan(MaturityLevel.developing, .mature)
        XCTAssertFalse(MaturityLevel.mature < .coldStart)
    }

    // MARK: - Display Names

    func testDisplayNames() {
        XCTAssertEqual(MaturityLevel.coldStart.displayName, "Starting")
        XCTAssertEqual(MaturityLevel.learning.displayName, "Learning")
        XCTAssertEqual(MaturityLevel.developing.displayName, "Developing")
        XCTAssertEqual(MaturityLevel.mature.displayName, "Mature")
    }
}
