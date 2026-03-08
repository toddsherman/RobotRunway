import Foundation
import os

/// Centralized logging using Apple's unified logging system.
///
/// Logs are managed by the OS — no file rotation, no unbounded growth.
/// View live logs with:
///   log stream --predicate 'subsystem == "com.robotrunway.app"'
/// Query past logs with:
///   log show --predicate 'subsystem == "com.robotrunway.app"' --last 10m
enum Log {
    private static let subsystem = "com.robotrunway.app"

    /// Activity monitoring: poll results, state transitions, classification
    static let monitor = Logger(subsystem: subsystem, category: "monitor")

    /// Shell commands: process execution, timeouts, errors
    static let shell = Logger(subsystem: subsystem, category: "shell")

    /// Activity profiles: learning updates, maturity transitions, persistence
    static let profile = Logger(subsystem: subsystem, category: "profile")

    /// UI: icon animation, menu updates, window lifecycle
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
