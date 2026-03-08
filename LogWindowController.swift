import Cocoa

/// Window that displays a real-time activity chart for debugging activity detection.
class LogWindowController: NSWindowController {

    private var chartView: ActivityChartView!
    private var refreshTimer: Timer?
    var logProvider: (() -> [PollLogEntry])?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Activity Log"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 250)

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window else { return }

        chartView = ActivityChartView(frame: window.contentView!.bounds)
        chartView.autoresizingMask = [.width, .height]
        window.contentView = chartView
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

    private func refresh() {
        chartView.entries = logProvider?() ?? []
        chartView.needsDisplay = true
    }
}
