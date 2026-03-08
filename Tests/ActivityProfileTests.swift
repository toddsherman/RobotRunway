import XCTest

class ActivityProfileTests: XCTestCase {

    func testFreshProfileIsColdStart() {
        let profile = ActivityProfile()
        XCTAssertEqual(profile.maturityLevel, .coldStart)
        XCTAssertEqual(profile.totalSamples, 0)
        XCTAssertEqual(profile.idleSamples, 0)
        XCTAssertEqual(profile.activeSamples, 0)
    }

    func testMaturityTransitions() {
        var profile = ActivityProfile()

        // Cold start: 0-5
        profile.totalSamples = 0
        XCTAssertEqual(profile.maturityLevel, .coldStart)

        // Transition to learning at 6
        profile.totalSamples = 6
        XCTAssertEqual(profile.maturityLevel, .learning)

        // Transition to developing at 60
        profile.totalSamples = 60
        XCTAssertEqual(profile.maturityLevel, .developing)

        // Transition to mature at 360
        profile.totalSamples = 360
        XCTAssertEqual(profile.maturityLevel, .mature)
    }

    func testSampleCountsAreIndependent() {
        var profile = ActivityProfile()
        profile.totalSamples = 100
        profile.idleSamples = 70
        profile.activeSamples = 30

        // Maturity is based only on totalSamples
        XCTAssertEqual(profile.maturityLevel, .developing)
        XCTAssertEqual(profile.idleSamples + profile.activeSamples, profile.totalSamples)
    }

    func testProfileVersionDefault() {
        let profile = ActivityProfile()
        XCTAssertEqual(profile.version, 1)
    }

    func testProfileEncodeDecode() throws {
        var profile = ActivityProfile()
        profile.totalSamples = 100
        profile.idleSamples = 60
        profile.activeSamples = 40
        profile.idleCPU.update(value: 5.0, alpha: 0.3)
        profile.activeCPU.update(value: 50.0, alpha: 0.3)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ActivityProfile.self, from: data)

        XCTAssertEqual(decoded.totalSamples, 100)
        XCTAssertEqual(decoded.idleSamples, 60)
        XCTAssertEqual(decoded.activeSamples, 40)
        XCTAssertEqual(decoded.idleCPU.mean, profile.idleCPU.mean, accuracy: 1e-10)
        XCTAssertEqual(decoded.activeCPU.mean, profile.activeCPU.mean, accuracy: 1e-10)
        XCTAssertEqual(decoded.maturityLevel, .developing)
    }

    func testProfileDictionaryEncodeDecode() throws {
        var profiles: [String: ActivityProfile] = [:]

        var p1 = ActivityProfile()
        p1.totalSamples = 10
        profiles["terminal"] = p1

        var p2 = ActivityProfile()
        p2.totalSamples = 400
        profiles["vscode"] = p2

        let data = try JSONEncoder().encode(profiles)
        let decoded = try JSONDecoder().decode([String: ActivityProfile].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded["terminal"]?.maturityLevel, .learning)
        XCTAssertEqual(decoded["vscode"]?.maturityLevel, .mature)
    }
}
