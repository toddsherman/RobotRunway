import Cocoa

/// Window that displays a rolling log of raw poll data for debugging activity detection.
class LogWindowController: NSWindowController {

    private var textView: NSTextView!
    private var refreshTimer: Timer?
    var logProvider: (() -> [PollLogEntry])?

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Activity Log"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 200)

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let window = window else { return }

        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        window.contentView = scrollView
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
        guard let entries = logProvider?() else { return }

        let lines = entries.map { formatEntry($0) }
        let header = "Time      App               CPU      Net  Children  Score       State"
        let separator = String(repeating: "─", count: 74)
        let text = header + "\n" + separator + "\n" + lines.joined(separator: "\n")

        let wasAtBottom = isScrolledToBottom()
        textView.string = text

        if wasAtBottom {
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func formatEntry(_ e: PollLogEntry) -> String {
        let time = Self.dateFormatter.string(from: e.timestamp)
        let app = (e.appName ?? "(none)").padding(toLength: 16, withPad: " ", startingAt: 0)
        let cpu = String(format: "%5.1f%%", e.cpu)
        let net = String(format: "%4d", e.connections)
        let children = String(format: "%8d", e.childCount)

        let scoreStr: String
        if let s = e.score, let t = e.threshold {
            scoreStr = String(format: "%5.3f/%4.2f", s, t)
        } else {
            scoreStr = "  heuristic"
        }

        let arrow = e.isActive ? "→" : " "
        return "\(time)  \(app)  \(cpu)  \(net)  \(children)  \(scoreStr)  \(arrow) \(e.stateLabel)"
    }

    private func isScrolledToBottom() -> Bool {
        guard let scrollView = textView.enclosingScrollView else { return true }
        let visibleRect = scrollView.contentView.bounds
        let contentHeight = textView.frame.height
        return visibleRect.maxY >= contentHeight - 20
    }
}
