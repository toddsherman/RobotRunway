import Cocoa
import os

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Components

    private var statusItem: NSStatusItem!
    private let activityMonitor = ActivityMonitor()
    private let sleepManager = SleepManager()
    private var settingsController: SettingsWindowController?
    private var logController: LogWindowController?
    private var onboardingController: OnboardingWindowController?
    private var pollTimer: Timer?
    private var isPaused = false

    /// Background queue for polling — keeps ps/lsof off the main thread.
    private let pollQueue = DispatchQueue(label: "com.robotrunway.poll", qos: .utility)

    // MARK: - Menu Items (updated dynamically)

    private var statusMenuItem: NSMenuItem!
    private var detailMenuItem: NSMenuItem!
    private var signalMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var appsMenuItem: NSMenuItem!

    // MARK: - Icon Animation

    private var iconSleep: NSImage!
    private var iconWake1: NSImage!
    private var iconWake2: NSImage!
    private var wakeAnimationFrame: Int = 0  // 0 = wake1, 1 = wake2
    private var animationTimer: Timer?
    private var isShowingActive = false       // current icon state
    private var lastActiveTime: Date = .distantPast  // when activity last detected

    // MARK: - User Preferences

    private var idleThresholdSeconds: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: "idleThreshold")
            return val > 0 ? val : 120
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "idleThreshold")
            activityMonitor.idleThresholdSeconds = newValue
        }
    }

    private let pollInterval: TimeInterval = 0.5

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        activityMonitor.idleThresholdSeconds = idleThresholdSeconds
        loadIcons()
        buildStatusItem()

        Log.ui.info("RobotRunway launched")

        if !UserDefaults.standard.bool(forKey: "didCompleteOnboarding") {
            showOnboarding()
        } else {
            startPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityMonitor.saveProfiles()
        sleepManager.allowSleep()
        Log.ui.info("RobotRunway terminated")
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        onboardingController = OnboardingWindowController()
        onboardingController?.onComplete = { [weak self] in
            self?.onboardingController = nil
            self?.refreshAppsMenuItem()
            self?.startPolling()
        }
        onboardingController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Icons

    private func loadIcons() {
        let bundle = Bundle.main
        let resourcePath = bundle.resourcePath ?? ""

        func loadIcon(_ filename: String) -> NSImage {
            let path = (resourcePath as NSString).appendingPathComponent(filename)
            guard let image = NSImage(contentsOfFile: path) else {
                // Fallback to SF Symbol if PNG not found
                return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)!
            }
            image.isTemplate = true
            image.size = NSSize(width: image.size.width / 2.67, height: image.size.height / 2.67)
            return image
        }

        iconSleep = loadIcon("robot-sleep.png")
        iconWake1 = loadIcon("robot-wake-1.png")
        iconWake2 = loadIcon("robot-wake-2.png")
    }

    // MARK: - Status Bar

    /// Build the status item once. Subsequent updates go through updateUI() or refreshAppsMenuItem().
    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.image = iconSleep
        button.imagePosition = .imageLeading

        let menu = NSMenu()

        statusMenuItem = makeInfoItem("Status: Starting…")
        menu.addItem(statusMenuItem)

        detailMenuItem = makeInfoItem("—")
        menu.addItem(detailMenuItem)

        signalMenuItem = makeInfoItem("Signals: —")
        menu.addItem(signalMenuItem)

        menu.addItem(NSMenuItem.separator())

        toggleMenuItem = NSMenuItem(title: "Pause Monitoring", action: #selector(togglePause), keyEquivalent: "p")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        // Idle threshold submenu
        let thresholdMenu = NSMenu()
        for (label, seconds) in [("1 min", 60), ("2 min", 120), ("3 min", 180), ("5 min", 300), ("10 min", 600)] {
            let item = NSMenuItem(title: label, action: #selector(setThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            if TimeInterval(seconds) == idleThresholdSeconds { item.state = .on }
            thresholdMenu.addItem(item)
        }
        let thresholdItem = NSMenuItem(title: "Stay Awake After Idle", action: nil, keyEquivalent: "")
        thresholdItem.submenu = thresholdMenu
        menu.addItem(thresholdItem)

        // Enabled apps indicator (updated dynamically)
        let enabledCount = HostAppRegistry.enabledApps.count
        appsMenuItem = NSMenuItem(
            title: "\(enabledCount) app\(enabledCount == 1 ? "" : "s") monitored",
            action: nil, keyEquivalent: ""
        )
        appsMenuItem.isEnabled = false
        menu.addItem(appsMenuItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let logItem = NSMenuItem(title: "Activity Log…", action: #selector(openLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        let quitItem = NSMenuItem(title: "Quit RobotRunway", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Update just the apps-monitored count in the existing menu.
    private func refreshAppsMenuItem() {
        let enabledCount = HostAppRegistry.enabledApps.count
        appsMenuItem.title = "\(enabledCount) app\(enabledCount == 1 ? "" : "s") monitored"
    }

    private func makeInfoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.dispatchPoll()
        }
        // No animation timer here — started on-demand when activity is detected.
        Log.ui.info("Polling started (interval: \(self.pollInterval)s)")
        dispatchPoll()
    }

    /// Dispatch poll() to background queue, then update UI on main thread.
    private func dispatchPoll() {
        // Capture isPaused on main thread before dispatching
        let paused = isPaused
        pollQueue.async { [weak self] in
            guard let self else { return }

            if paused {
                DispatchQueue.main.async {
                    self.sleepManager.allowSleep()
                    self.updateUI(state: .paused)
                }
                return
            }

            let state = self.activityMonitor.poll()

            DispatchQueue.main.async {
                switch state {
                case .noSession, .idle:
                    self.sleepManager.allowSleep()
                case .active, .idleCooldown:
                    self.sleepManager.preventSleep()
                case .paused:
                    self.sleepManager.allowSleep()
                }
                self.updateUI(state: state)
            }
        }
    }

    // MARK: - Icon Animation (demand-driven)

    /// Start the animation timer if not already running.
    private func startAnimationIfNeeded() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.animateIcon()
        }
    }

    /// Stop the animation timer and show the sleep icon.
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        statusItem.button?.image = iconSleep
        wakeAnimationFrame = 0
    }

    private func animateIcon() {
        guard let button = statusItem.button else { return }

        if isShowingActive {
            // Alternate wake frames every 0.1s
            button.image = (wakeAnimationFrame == 0) ? iconWake1 : iconWake2
            wakeAnimationFrame = 1 - wakeAnimationFrame
        } else {
            // Keep animating during 5-second grace period after activity stops
            let idleFor = Date().timeIntervalSince(lastActiveTime)
            if idleFor > 5.0 {
                stopAnimation()
            } else {
                button.image = (wakeAnimationFrame == 0) ? iconWake1 : iconWake2
                wakeAnimationFrame = 1 - wakeAnimationFrame
            }
        }
    }

    // MARK: - UI Update

    private func updateUI(state: MonitorState) {
        // Track active state for icon animation
        if case .active = state {
            isShowingActive = true
            lastActiveTime = Date()
            startAnimationIfNeeded()
        } else {
            isShowingActive = false
            // Animation timer will self-stop after 5s grace period
        }

        switch state {
        case .noSession:
            statusMenuItem.title = "No AI coding session found"
            detailMenuItem.title = "Mac can sleep normally"
            signalMenuItem.title = "Watching \(HostAppRegistry.enabledApps.count) app(s)"

        case .active(_, let cpu, let connections, let confidence):
            statusMenuItem.title = "Keeping Mac awake"
            detailMenuItem.title = "AI activity detected"
            signalMenuItem.title = String(format: "CPU: %.1f%%  Net: %d conn  [%@]", cpu, connections, confidence.displayName)

        case .idleCooldown(_, let elapsed, let threshold):
            statusMenuItem.title = "Forcing awake for \(fmt(threshold - elapsed))"
            detailMenuItem.title = "AI activity paused"
            signalMenuItem.title = "Waiting for idle threshold"

        case .idle(_, let duration):
            statusMenuItem.title = "Sleep allowed"
            detailMenuItem.title = "AI apps idle for \(fmt(duration))"
            signalMenuItem.title = "All signals below baseline"

        case .paused:
            statusMenuItem.title = "Monitoring paused"
            detailMenuItem.title = "Mac can sleep normally"
            signalMenuItem.title = "—"
        }
    }

    private func fmt(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }

    // MARK: - Actions

    @objc private func togglePause() {
        isPaused.toggle()
        toggleMenuItem.title = isPaused ? "Resume Monitoring" : "Pause Monitoring"
        if isPaused {
            sleepManager.allowSleep()
            Log.ui.info("Monitoring paused")
        } else {
            Log.ui.info("Monitoring resumed")
        }
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        idleThresholdSeconds = TimeInterval(sender.tag)
        if let menu = sender.menu {
            for item in menu.items { item.state = (item.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
            settingsController?.profileProvider = { [weak self] appId in
                self?.activityMonitor.profile(forAppId: appId)
            }
            settingsController?.onSettingsChanged = { [weak self] in
                self?.refreshAppsMenuItem()
            }
            settingsController?.onRecalibrate = { [weak self] _ in
                self?.activityMonitor.resetAllProfiles()
            }
        }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openLog() {
        if logController == nil {
            logController = LogWindowController()
            logController?.logProvider = { [weak self] in
                self?.activityMonitor.currentPollLog() ?? []
            }
        }
        logController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        activityMonitor.saveProfiles()
        sleepManager.allowSleep()
        NSApp.terminate(nil)
    }
}
