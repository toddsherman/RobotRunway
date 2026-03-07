import Cocoa

/// First-launch setup window where the user selects which apps they use AI coding assistants in.
class OnboardingWindowController: NSWindowController {

    private var checkboxes: [(HostApp, NSButton)] = []
    var onComplete: (() -> Void)?

    convenience init() {
        // Compute height dynamically: header area + checkboxes + button area
        let headerHeight: CGFloat = 282
        let checkboxHeight: CGFloat = CGFloat(HostAppRegistry.allApps.count) * 26
        let buttonArea: CGFloat = 64
        let windowHeight = headerHeight + checkboxHeight + buttonArea

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: windowHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to RobotRunway"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        var y = contentView.bounds.height - 36

        // App name
        let titleLabel = makeLabel("RobotRunway", bold: true, size: 20)
        titleLabel.frame = NSRect(x: 24, y: y, width: 432, height: 28)
        contentView.addSubview(titleLabel)
        y -= 32

        // Tagline
        let tagline = makeLabel("Keep your Mac awake while AI coding assistants are working.")
        tagline.frame = NSRect(x: 24, y: y, width: 432, height: 18)
        tagline.font = NSFont.systemFont(ofSize: 13)
        tagline.textColor = .secondaryLabelColor
        contentView.addSubview(tagline)
        y -= 36

        // Explanation
        let explanation = makeLabel(
            "RobotRunway sits in your menu bar and monitors AI coding activity " +
            "(Claude, Codex, Gemini). It prevents your Mac from sleeping during " +
            "active work and allows sleep when idle."
        )
        explanation.frame = NSRect(x: 24, y: y - 32, width: 432, height: 48)
        explanation.font = NSFont.systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 3
        explanation.lineBreakMode = .byWordWrapping
        contentView.addSubview(explanation)
        y -= 68

        // Learning explanation
        let learningNote = makeLabel(
            "Activity detection improves over time. RobotRunway continuously learns " +
            "each app's patterns to precisely distinguish active work from idle sessions."
        )
        learningNote.frame = NSRect(x: 24, y: y - 32, width: 432, height: 48)
        learningNote.font = NSFont.systemFont(ofSize: 12)
        learningNote.textColor = .secondaryLabelColor
        learningNote.maximumNumberOfLines = 3
        learningNote.lineBreakMode = .byWordWrapping
        contentView.addSubview(learningNote)
        y -= 68

        // Section header
        let sectionLabel = makeLabel("Which apps do you use AI coding assistants in?", bold: true)
        sectionLabel.frame = NSRect(x: 24, y: y, width: 432, height: 18)
        contentView.addSubview(sectionLabel)
        y -= 8

        let hint = makeLabel("Installed apps are pre-selected. Uncheck any you don't use.")
        hint.frame = NSRect(x: 24, y: y - 14, width: 432, height: 14)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        contentView.addSubview(hint)
        y -= 34

        // App checkboxes
        for app in HostAppRegistry.allApps {
            let isInstalled = isAppInstalled(app)

            let checkbox = NSButton(checkboxWithTitle: "  " + app.displayName, target: nil, action: nil)
            checkbox.state = isInstalled ? .on : .off
            checkbox.isEnabled = isInstalled
            checkbox.tag = HostAppRegistry.allApps.firstIndex(where: { $0.id == app.id }) ?? 0
            checkbox.frame = NSRect(x: 28, y: y, width: 200, height: 22)
            contentView.addSubview(checkbox)
            checkboxes.append((app, checkbox))

            if !isInstalled {
                let notInstalled = makeLabel("Not installed")
                notInstalled.frame = NSRect(x: 234, y: y + 2, width: 120, height: 16)
                notInstalled.font = NSFont.systemFont(ofSize: 11)
                notInstalled.textColor = .disabledControlTextColor
                contentView.addSubview(notInstalled)
            }

            y -= 26
        }

        y -= 16

        // Get Started button
        let startButton = NSButton(title: "Get Started", target: self, action: #selector(completeOnboarding))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.frame = NSRect(x: contentView.bounds.width - 140, y: 16, width: 120, height: 32)
        startButton.autoresizingMask = [.minXMargin]
        contentView.addSubview(startButton)
    }

    private func isAppInstalled(_ app: HostApp) -> Bool {
        guard let bundleId = app.bundleIdentifier else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    private func makeLabel(_ text: String, bold: Bool = false, size: CGFloat = 13) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }

    @objc private func completeOnboarding() {
        // Save enabled apps based on checkbox state
        for (app, checkbox) in checkboxes {
            app.isEnabled = (checkbox.state == .on)
        }

        UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")

        window?.close()
        onComplete?()
    }
}
