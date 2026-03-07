import Foundation
import IOKit
import IOKit.pwr_mgt

/// Manages macOS sleep prevention using IOPMLib power assertions.
///
/// Creates two assertions when engaged:
/// - `PreventUserIdleSystemSleep`: Prevents the Mac from sleeping due to inactivity.
/// - `PreventUserIdleDisplaySleep`: Prevents the display from dimming/sleeping.
class SleepManager {

    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private(set) var isPreventingSleep = false

    private let reason = "RobotRunway: AI coding assistant is actively working" as CFString

    /// Engage both sleep prevention assertions.
    func preventSleep() {
        guard !isPreventingSleep else { return }

        let sysResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemAssertionID
        )

        let dispResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayAssertionID
        )

        if sysResult == kIOReturnSuccess && dispResult == kIOReturnSuccess {
            isPreventingSleep = true
        } else {
            // Clean up partial success
            if sysResult == kIOReturnSuccess { IOPMAssertionRelease(systemAssertionID) }
            if dispResult == kIOReturnSuccess { IOPMAssertionRelease(displayAssertionID) }
            NSLog("[RobotRunway] Failed to create power assertions: sys=%d disp=%d", sysResult, dispResult)
        }
    }

    /// Release assertions, allowing the Mac to sleep normally.
    func allowSleep() {
        guard isPreventingSleep else { return }
        IOPMAssertionRelease(systemAssertionID)
        IOPMAssertionRelease(displayAssertionID)
        systemAssertionID = 0
        displayAssertionID = 0
        isPreventingSleep = false
    }

    deinit { allowSleep() }
}
