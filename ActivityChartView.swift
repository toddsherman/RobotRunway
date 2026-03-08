import Cocoa

/// Custom NSView that draws a real-time multi-signal activity chart.
class ActivityChartView: NSView {

    var entries: [PollLogEntry] = []

    // Chart margins (y-axis labels are in a separate fixed view)
    private let marginLeft: CGFloat = 4
    private let marginRight: CGFloat = 12
    private let marginTop: CGFloat = 12
    private let marginBottom: CGFloat = 28

    // Line colors
    private let scoreColor = NSColor.systemBlue
    private let cpuColor = NSColor.systemOrange
    private let connectionsColor = NSColor.systemGreen
    private let childrenColor = NSColor.systemPurple
    private let thresholdColor = NSColor.systemRed

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let chartRect = NSRect(
            x: marginLeft,
            y: marginBottom,
            width: bounds.width - marginLeft - marginRight,
            height: bounds.height - marginTop - marginBottom
        )

        drawBackground(ctx, chartRect: chartRect)
        drawActiveRegions(ctx, chartRect: chartRect)
        drawGridAndAxes(ctx, chartRect: chartRect)
        drawThresholdLine(ctx, chartRect: chartRect)
        drawDataLines(ctx, chartRect: chartRect)
    }

    // MARK: - Time Range

    private func timeRange() -> (start: Date, end: Date) {
        let now = Date()
        let start = now.addingTimeInterval(-600) // 10 minutes ago
        return (start, now)
    }

    private func xPosition(for date: Date, in chartRect: NSRect) -> CGFloat {
        let (start, end) = timeRange()
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return chartRect.minX }
        let fraction = date.timeIntervalSince(start) / total
        return chartRect.minX + CGFloat(fraction) * chartRect.width
    }

    private func yPosition(for value: Double, in chartRect: NSRect) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return chartRect.minY + CGFloat(clamped) * chartRect.height
    }

    // MARK: - Drawing

    private func drawBackground(_ ctx: CGContext, chartRect: NSRect) {
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(chartRect)

        // Chart border
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(chartRect)
    }

    private func drawActiveRegions(_ ctx: CGContext, chartRect: NSRect) {
        guard entries.count >= 2 else { return }

        let activeColor = NSColor.systemGreen.withAlphaComponent(0.08).cgColor
        ctx.setFillColor(activeColor)

        var i = 0
        while i < entries.count {
            if entries[i].isActive {
                let startX = xPosition(for: entries[i].timestamp, in: chartRect)
                var endX = startX

                // Find the end of this active region
                while i < entries.count && entries[i].isActive {
                    endX = xPosition(for: entries[i].timestamp, in: chartRect)
                    i += 1
                }

                let rect = NSRect(
                    x: max(startX, chartRect.minX),
                    y: chartRect.minY,
                    width: max(endX - startX, 2),
                    height: chartRect.height
                )
                ctx.fill(rect)
            } else {
                i += 1
            }
        }
    }

    private func drawGridAndAxes(_ ctx: CGContext, chartRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // Y-axis grid lines (labels drawn in separate fixed YAxisView)
        ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(0.5)

        for i in 0...5 {
            let value = Double(i) * 0.2
            let y = yPosition(for: value, in: chartRect)

            ctx.move(to: CGPoint(x: chartRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            ctx.strokePath()
        }

        // X-axis time labels (every minute)
        let (start, _) = timeRange()
        for minute in 0...10 {
            let date = start.addingTimeInterval(Double(minute) * 60)
            let x = xPosition(for: date, in: chartRect)

            // Tick
            ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
            ctx.move(to: CGPoint(x: x, y: chartRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: chartRect.maxY))
            ctx.strokePath()

            // Label (every 2 minutes to avoid crowding)
            if minute % 2 == 0 {
                let label = Self.timeFormatter.string(from: date)
                let size = label.size(withAttributes: attrs)
                label.draw(at: NSPoint(x: x - size.width / 2, y: chartRect.minY - size.height - 2), withAttributes: attrs)
            }
        }
    }

    private func drawThresholdLine(_ ctx: CGContext, chartRect: NSRect) {
        // Plot threshold as a time-series line (changes as profile matures)
        let thresholdPoints = entries.compactMap { e -> (timestamp: Date, value: Double)? in
            guard let t = e.threshold else { return nil }
            return (timestamp: e.timestamp, value: t)
        }
        drawLine(ctx, chartRect: chartRect, color: thresholdColor, lineWidth: 1.5, points: thresholdPoints)
    }

    private func drawDataLines(_ ctx: CGContext, chartRect: NSRect) {
        guard !entries.isEmpty else { return }

        // Compute max values for normalization
        let maxCPU = max(entries.map(\.cpu).max() ?? 1, 1)
        let maxConn = max(Double(entries.map(\.connections).max() ?? 1), 1)
        let maxChildren = max(Double(entries.map(\.childCount).max() ?? 1), 1)

        // Draw supporting lines at 50% transparency
        drawLine(ctx, chartRect: chartRect, color: childrenColor.withAlphaComponent(0.5), lineWidth: 0.75,
                 points: entries.map { (timestamp: $0.timestamp, value: Double($0.childCount) / maxChildren) })

        drawLine(ctx, chartRect: chartRect, color: connectionsColor.withAlphaComponent(0.5), lineWidth: 0.75,
                 points: entries.map { (timestamp: $0.timestamp, value: Double($0.connections) / maxConn) })

        drawLine(ctx, chartRect: chartRect, color: cpuColor.withAlphaComponent(0.5), lineWidth: 0.75,
                 points: entries.map { (timestamp: $0.timestamp, value: $0.cpu / maxCPU) })

        // Score line — prominent, skip nil values (cold start)
        let scorePoints = entries.compactMap { e -> (timestamp: Date, value: Double)? in
            guard let s = e.score else { return nil }
            return (timestamp: e.timestamp, value: s)
        }
        drawLine(ctx, chartRect: chartRect, color: scoreColor, lineWidth: 2.0, points: scorePoints)
    }

    private func drawLine(_ ctx: CGContext, chartRect: NSRect, color: NSColor, lineWidth: CGFloat,
                           points: [(timestamp: Date, value: Double)]) {
        guard points.count >= 2 else { return }

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        let first = points[0]
        ctx.move(to: CGPoint(x: xPosition(for: first.timestamp, in: chartRect),
                              y: yPosition(for: first.value, in: chartRect)))

        for point in points.dropFirst() {
            ctx.addLine(to: CGPoint(x: xPosition(for: point.timestamp, in: chartRect),
                                     y: yPosition(for: point.value, in: chartRect)))
        }
        ctx.strokePath()
    }

}
