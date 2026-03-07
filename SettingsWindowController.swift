import Cocoa

/// Preferences window where the user selects which host apps to monitor
/// and manages learned profiles.
class SettingsWindowController: NSWindowController {

    private var checkboxes: [(HostApp, NSButton)] = []
    var onSettingsChanged: (() -> Void)?
    var onRecalibrate: ((String) -> Void)?
    var profileProvider: ((String) -> ActivityProfile?)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeAwake Settings"
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

        var y = contentView.bounds.height - 40

        // Title
        let titleLabel = makeLabel("Monitor Claude Code in these apps:", bold: true)
        titleLabel.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        contentView.addSubview(titleLabel)
        y -= 10

        let subtitleLabel = makeLabel("Installed apps are auto-detected. Enable the ones you use.")
        subtitleLabel.frame = NSRect(x: 20, y: y - 16, width: 380, height: 16)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        contentView.addSubview(subtitleLabel)
        y -= 38

        // App checkboxes
        for app in HostAppRegistry.allApps {
            let isInstalled = isAppInstalled(app)

            let checkbox = NSButton(checkboxWithTitle: "  " + app.displayName, target: self, action: #selector(toggleApp(_:)))
            checkbox.state = app.isEnabled ? .on : .off
            checkbox.isEnabled = isInstalled
            checkbox.tag = HostAppRegistry.allApps.firstIndex(where: { $0.id == app.id }) ?? 0
            checkbox.frame = NSRect(x: 24, y: y, width: 200, height: 22)
            contentView.addSubview(checkbox)
            checkboxes.append((app, checkbox))

            // Status label
            let profile = profileProvider?(app.id)
            let statusLabel = makeLabel(statusText(for: app, installed: isInstalled, profile: profile))
            statusLabel.frame = NSRect(x: 230, y: y + 2, width: 160, height: 16)
            statusLabel.font = NSFont.systemFont(ofSize: 11)
            statusLabel.textColor = isInstalled ? .tertiaryLabelColor : .disabledControlTextColor
            contentView.addSubview(statusLabel)

            y -= 30
        }

        y -= 10

        // Separator
        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 20, y: y, width: 380, height: 1)
        contentView.addSubview(sep)
        y -= 24

        // Reset button
        let recalButton = NSButton(title: "Reset All Learned Profiles", target: self, action: #selector(resetProfiles))
        recalButton.bezelStyle = .rounded
        recalButton.frame = NSRect(x: 20, y: y, width: 200, height: 28)
        contentView.addSubview(recalButton)

        let recalNote = makeLabel("Resets to cautious defaults")
        recalNote.frame = NSRect(x: 228, y: y + 6, width: 180, height: 16)
        recalNote.font = NSFont.systemFont(ofSize: 11)
        recalNote.textColor = .tertiaryLabelColor
        contentView.addSubview(recalNote)

        y -= 40

        // Info text
        let infoLabel = makeLabel(
            "ClaudeAwake continuously learns each app's activity patterns using " +
            "network, CPU, and process signals. Profiles become more accurate " +
            "over time. Reset profiles if your workflow has changed significantly."
        )
        infoLabel.frame = NSRect(x: 20, y: y - 30, width: 380, height: 48)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.maximumNumberOfLines = 3
        infoLabel.lineBreakMode = .byWordWrapping
        contentView.addSubview(infoLabel)
    }

    private func isAppInstalled(_ app: HostApp) -> Bool {
        guard let bundleId = app.bundleIdentifier else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    private func statusText(for app: HostApp, installed: Bool, profile: ActivityProfile?) -> String {
        if !installed { return "Not installed" }
        guard app.isEnabled else { return "Disabled" }
        guard let p = profile else { return "No data yet" }

        switch p.maturityLevel {
        case .coldStart:  return "Starting (\(p.totalSamples) samples)"
        case .learning:   return "Learning (\(p.totalSamples) samples)"
        case .developing: return "Good (\(p.totalSamples) samples)"
        case .mature:     return "Mature (\(p.totalSamples) samples)"
        }
    }

    private func makeLabel(_ text: String, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        if bold { label.font = NSFont.boldSystemFont(ofSize: 13) }
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }

    @objc private func toggleApp(_ sender: NSButton) {
        let index = sender.tag
        guard index < HostAppRegistry.allApps.count else { return }
        let app = HostAppRegistry.allApps[index]
        app.isEnabled = (sender.state == .on)
        onSettingsChanged?()
    }

    @objc private func resetProfiles() {
        let alert = NSAlert()
        alert.messageText = "Reset Learned Profiles?"
        alert.informativeText = "This will clear all learned activity patterns. ClaudeAwake will start fresh with cautious defaults and re-learn over time."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            onRecalibrate?("all")
        }
    }
}
