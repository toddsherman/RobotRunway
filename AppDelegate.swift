import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Components

    private var statusItem: NSStatusItem!
    private let activityMonitor = ActivityMonitor()
    private let sleepManager = SleepManager()
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var pollTimer: Timer?
    private var isPaused = false

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

        if !UserDefaults.standard.bool(forKey: "didCompleteOnboarding") {
            showOnboarding()
        } else {
            startPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityMonitor.saveProfiles()
        sleepManager.allowSleep()
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
            self?.tick()
        }
        tick()
    }

    private func tick() {
        if isPaused {
            sleepManager.allowSleep()
            updateUI(state: .paused)
            return
        }

        let state = activityMonitor.poll()

        switch state {
        case .noSession, .idle:
            sleepManager.allowSleep()
        case .active, .idleCooldown:
            sleepManager.preventSleep()
        case .paused:
            sleepManager.allowSleep()
        }

        updateUI(state: state)
    }

    // MARK: - UI Update

    private func updateUI(state: MonitorState) {
        guard let button = statusItem.button else { return }

        // Icon reflects real-time AI activity state
        let claudeActive: Bool
        if case .active = state { claudeActive = true } else { claudeActive = false }

        if claudeActive {
            // Alternate between wake 1 and wake 2 each poll tick (0.5s)
            button.image = (wakeAnimationFrame == 0) ? iconWake1 : iconWake2
            wakeAnimationFrame = 1 - wakeAnimationFrame
        } else {
            button.image = iconSleep
            wakeAnimationFrame = 0
        }

        switch state {
        case .noSession:
            statusMenuItem.title = "No AI coding session found"
            detailMenuItem.title = "Mac can sleep normally"
            signalMenuItem.title = "Watching \(HostAppRegistry.enabledApps.count) app(s)"

        case .active(let appName, let cpu, let connections, let confidence):
            statusMenuItem.title = "Keeping Mac awake"
            detailMenuItem.title = "Active in \(appName)"
            signalMenuItem.title = String(format: "CPU: %.1f%%  Net: %d conn  [%@]", cpu, connections, confidence.displayName)

        case .idleCooldown(let appName, let elapsed, let threshold):
            statusMenuItem.title = "Staying awake \(fmt(threshold - elapsed)) more"
            detailMenuItem.title = "Idle in \(appName)"
            signalMenuItem.title = "Idle: \(fmt(elapsed)) / \(fmt(threshold))"

        case .idle(let appName, let duration):
            statusMenuItem.title = "Sleep allowed"
            detailMenuItem.title = "Idle in \(appName) for \(fmt(duration))"
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
        if isPaused { sleepManager.allowSleep() }
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

    @objc private func quit() {
        activityMonitor.saveProfiles()
        sleepManager.allowSleep()
        NSApp.terminate(nil)
    }
}
