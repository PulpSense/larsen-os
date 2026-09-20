import AppKit
import SwiftUI

@MainActor
final class YearProgressDesktopPanelController {
    static let shared = YearProgressDesktopPanelController()

    private let enabledKey = "desktopYearProgressPanelEnabled"
    private var panel: DesktopWallPanel?

    private init() {}

    func restoreIfEnabled() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey)
        if enabled { present() }
    }

    func present() {
        UserDefaults.standard.set(true, forKey: enabledKey)
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 360, height: 260),
            minimumSize: NSSize(width: 280, height: 210),
            frameAutosaveName: "DigitalWallYearProgressDesktopPanelCompact",
            defaultAnchor: .topLeft,
            defaultOffset: NSPoint(x: 36, y: 310)
        ) {
            YearProgressDesktopPanelContent { [weak self] in
                self?.dismiss()
            }
        }

        self.panel = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct YearProgressDesktopPanelContent: View {
    let close: () -> Void
    @State private var controlsVisible = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        let year = TrackerCalendar.calendar.component(.year, from: now)

        return ZStack {
            DesktopPanelBackground()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Year Elapsed")
                            .font(.headline)
                            .foregroundStyle(.indigo)
                        Text(String(year))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(yearProgress(now: now), format: .percent.precision(.fractionLength(1)))
                        .font(.title3.bold().monospacedDigit())

                    DesktopPanelControlMenu(isVisible: controlsVisible) {
                        Button("Close", systemImage: "xmark", role: .destructive, action: close)
                    }
                }

                YearProgressGrid(year: year, now: now)
                    .frame(maxHeight: .infinity)
            }
            .padding(18)

        }
        .onHover { controlsVisible = $0 }
    }

    private func yearProgress(now: Date) -> Double {
        let calendar = TrackerCalendar.calendar
        guard let start = calendar.date(from: DateComponents(
            year: calendar.component(.year, from: now),
            month: 1,
            day: 1
        )), let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 0 }
        let elapsed = min(max(0, now.timeIntervalSince(start)), end.timeIntervalSince(start))
        return elapsed / end.timeIntervalSince(start)
    }
}

private struct YearProgressGrid: View {
    let year: Int
    let now: Date

    var body: some View {
        GeometryReader { proxy in
            let days = daysInYear
            let spacing: CGFloat = 2
            let layout = bestLayout(
                itemCount: days.count,
                size: proxy.size,
                spacing: spacing
            )

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(layout.cell), spacing: spacing),
                    count: layout.columns
                ),
                alignment: .center,
                spacing: spacing
            ) {
                ForEach(days, id: \.self) { date in
                    RoundedRectangle(cornerRadius: max(1, layout.cell * 0.22))
                        .fill(color(for: date))
                        .overlay {
                            if TrackerCalendar.calendar.isDate(date, inSameDayAs: now) {
                                RoundedRectangle(cornerRadius: max(1, layout.cell * 0.22))
                                    .stroke(.primary.opacity(0.72), lineWidth: 1)
                            }
                        }
                        .frame(width: layout.cell, height: layout.cell)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var daysInYear: [Date] {
        let calendar = TrackerCalendar.calendar
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return [] }
        let count = calendar.dateComponents([.day], from: start, to: end).day ?? 365
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func bestLayout(
        itemCount: Int,
        size: CGSize,
        spacing: CGFloat
    ) -> (columns: Int, cell: CGFloat) {
        guard itemCount > 0 else { return (1, 1) }

        return (1...itemCount).reduce((columns: 1, cell: CGFloat(0))) { best, columns in
            let rows = Int(ceil(Double(itemCount) / Double(columns)))
            let cellWidth = (size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let cellHeight = (size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            let cell = max(1, min(cellWidth, cellHeight))
            return cell > best.cell ? (columns, cell) : best
        }
    }

    private func color(for date: Date) -> Color {
        let calendar = TrackerCalendar.calendar
        let today = calendar.startOfDay(for: now)
        if date < today { return .indigo }
        if calendar.isDate(date, inSameDayAs: now) { return .indigo.opacity(0.58) }
        return .secondary.opacity(0.12)
    }
}
