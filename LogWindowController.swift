import Cocoa

/// Fixed y-axis labels (0.0–1.0) that stay visible when chart scrolls horizontally.
class YAxisView: NSView {
    private let marginTop: CGFloat = 12
    private let marginBottom: CGFloat = 28

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let chartHeight = bounds.height - marginTop - marginBottom

        for i in 0...5 {
            let value = Double(i) * 0.2
            let y = marginBottom + CGFloat(value) * chartHeight

            let label = String(format: "%.1f", value)
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: bounds.width - size.width - 4, y: y - size.height / 2), withAttributes: attrs)
        }
    }
}

/// Window that displays a real-time per-app activity chart for debugging activity detection.
class LogWindowController: NSWindowController {

    private var chartView: ActivityChartView!
    private var scrollView: NSScrollView!
    private var yAxisView: YAxisView!
    private var tabControl: NSSegmentedControl!
    private var legendView: NSView!
    private var refreshTimer: Timer?
    var logProvider: (() -> [PollLogEntry])?

    /// App names currently shown as tabs, in display order.
    private var appNames: [String] = []
    /// Currently selected app name (nil = "All").
    private var selectedApp: String?

    /// Chart width = scroll view width × this factor (10 screens for 10 minutes → ~1 min visible).
    private let chartWidthMultiplier: CGFloat = 10

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

        // Legend row (sticky, between tabs and chart)
        legendView = buildLegend()
        legendView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(legendView)

        // Fixed y-axis labels
        yAxisView = YAxisView()
        yAxisView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(yAxisView)

        // Scroll view wrapping the chart
        scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        container.addSubview(scrollView)

        chartView = ActivityChartView()
        scrollView.documentView = chartView

        let yAxisWidth: CGFloat = 36

        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            tabControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            tabControl.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            tabControl.heightAnchor.constraint(equalToConstant: 24),

            legendView.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 6),
            legendView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            legendView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            legendView.heightAnchor.constraint(equalToConstant: 16),

            yAxisView.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 4),
            yAxisView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            yAxisView.widthAnchor.constraint(equalToConstant: yAxisWidth),
            yAxisView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: yAxisView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        window.contentView = container
    }

    private func buildLegend() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 14

        let items: [(String, NSColor)] = [
            ("Score", .systemBlue),
            ("CPU", .systemOrange),
            ("Network", .systemGreen),
            ("Children", .systemPurple),
            ("Threshold", .systemRed),
        ]

        for (label, color) in items {
            let swatch = NSView()
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = 1.5
            swatch.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 12),
                swatch.heightAnchor.constraint(equalToConstant: 3),
            ])

            let text = NSTextField(labelWithString: label)
            text.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            text.textColor = .labelColor

            let pair = NSStackView(views: [swatch, text])
            pair.orientation = .horizontal
            pair.spacing = 4
            pair.alignment = .centerY

            row.addArrangedSubview(pair)
        }

        return row
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

        let filtered: [PollLogEntry]
        if let app = selectedApp {
            filtered = allEntries.filter { $0.appName == app }
        } else {
            filtered = allEntries
        }

        // Size the chart: width = visible width × multiplier, height = scroll view height
        let visibleWidth = scrollView.contentSize.width
        let chartWidth = visibleWidth * chartWidthMultiplier
        let chartHeight = scrollView.contentSize.height

        let wasAtRight = isScrolledToRight()

        chartView.frame = NSRect(x: 0, y: 0, width: chartWidth, height: chartHeight)
        chartView.entries = filtered
        chartView.needsDisplay = true

        // Auto-scroll to right edge (most recent data) if user was already there
        if wasAtRight {
            scrollToRight()
        }
    }

    private func isScrolledToRight() -> Bool {
        let clipBounds = scrollView.contentView.bounds
        let docWidth = scrollView.documentView?.frame.width ?? 0
        return clipBounds.maxX >= docWidth - 20 || docWidth <= clipBounds.width
    }

    private func scrollToRight() {
        let docWidth = scrollView.documentView?.frame.width ?? 0
        let visibleWidth = scrollView.contentSize.width
        let maxX = max(docWidth - visibleWidth, 0)
        scrollView.contentView.scroll(to: NSPoint(x: maxX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateTabs(from entries: [PollLogEntry]) {
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

        tabControl.segmentCount = 1 + names.count
        tabControl.setLabel("All", forSegment: 0)
        tabControl.setWidth(40, forSegment: 0)
        for (i, name) in names.enumerated() {
            tabControl.setLabel(name, forSegment: i + 1)
            tabControl.setWidth(0, forSegment: i + 1)
        }

        if let app = selectedApp, let idx = names.firstIndex(of: app) {
            tabControl.selectedSegment = idx + 1
        } else {
            selectedApp = nil
            tabControl.selectedSegment = 0
        }
    }

    private func applyFilter() {
        let allEntries = logProvider?() ?? []
        let filtered: [PollLogEntry]
        if let app = selectedApp {
            filtered = allEntries.filter { $0.appName == app }
        } else {
            filtered = allEntries
        }

        chartView.entries = filtered
        chartView.needsDisplay = true
        scrollToRight()
    }
}
