import Cocoa

/// Window that displays a real-time per-app activity chart for debugging activity detection.
class LogWindowController: NSWindowController {

    private var chartView: ActivityChartView!
    private var tabControl: NSSegmentedControl!
    private var refreshTimer: Timer?
    var logProvider: (() -> [PollLogEntry])?

    /// App names currently shown as tabs, in display order.
    private var appNames: [String] = []
    /// Currently selected app name (nil = "All").
    private var selectedApp: String?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Activity Log"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 280)

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window else { return }

        let container = NSView(frame: window.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        // Tab bar at the top
        tabControl = NSSegmentedControl()
        tabControl.segmentStyle = .texturedSquare
        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabControl)

        // Chart fills the rest
        chartView = ActivityChartView()
        chartView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chartView)

        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            tabControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            tabControl.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            tabControl.heightAnchor.constraint(equalToConstant: 24),

            chartView.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 8),
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        window.contentView = container
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    @objc private func tabChanged() {
        let idx = tabControl.selectedSegment
        if idx == 0 {
            selectedApp = nil
        } else if idx - 1 < appNames.count {
            selectedApp = appNames[idx - 1]
        }
        applyFilter()
    }

    private func refresh() {
        let allEntries = logProvider?() ?? []
        updateTabs(from: allEntries)

        if let app = selectedApp {
            chartView.entries = allEntries.filter { $0.appName == app }
        } else {
            chartView.entries = allEntries
        }
        chartView.needsDisplay = true
    }

    private func updateTabs(from entries: [PollLogEntry]) {
        // Collect unique app names in order of first appearance
        var seen = Set<String>()
        var names: [String] = []
        for e in entries {
            if let name = e.appName, !seen.contains(name) {
                seen.insert(name)
                names.append(name)
            }
        }

        guard names != appNames else { return }
        appNames = names

        // Rebuild segments: "All" + each app
        tabControl.segmentCount = 1 + names.count
        tabControl.setLabel("All", forSegment: 0)
        tabControl.setWidth(40, forSegment: 0)
        for (i, name) in names.enumerated() {
            tabControl.setLabel(name, forSegment: i + 1)
            tabControl.setWidth(0, forSegment: i + 1) // auto-size
        }

        // Restore selection
        if let app = selectedApp, let idx = names.firstIndex(of: app) {
            tabControl.selectedSegment = idx + 1
        } else {
            selectedApp = nil
            tabControl.selectedSegment = 0
        }
    }

    private func applyFilter() {
        let allEntries = logProvider?() ?? []
        if let app = selectedApp {
            chartView.entries = allEntries.filter { $0.appName == app }
        } else {
            chartView.entries = allEntries
        }
        chartView.needsDisplay = true
    }
}
