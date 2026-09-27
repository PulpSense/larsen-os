import AppKit
import SwiftUI

@MainActor
final class YearProgressDesktopPanelController {
    static let shared = YearProgressDesktopPanelController()

    private let visibility = DesktopWidgetVisibility.shared
    private var panel: DesktopWallPanel?

    private init() {}

    func restoreIfEnabled() {
        if visibility.isVisible(.yearElapsed) { present() }
    }

    func present() {
        visibility.setVisible(true, for: .yearElapsed)
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
        visibility.setVisible(false, for: .yearElapsed)
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct YearProgressDesktopPanelContent: View {
    let hide: () -> Void
    @State private var controlsVisible = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        let progress = YearProgress(now: now, calendar: TrackerCalendar.calendar)
        let year = progress.year

        return ZStack(alignment: .bottomTrailing) {
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

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(progress.fractionElapsed, format: .percent.precision(.fractionLength(1)))
                            .font(.title3.bold().monospacedDigit())
                        Text("\(progress.daysElapsed) of \(progress.daysElapsed + progress.daysRemaining) days")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                }

                YearProgressGrid(year: year, now: now, compactCrosses: true)
                    .frame(maxHeight: .infinity)

            }
            .padding(18)

            DesktopPanelControlMenu(isVisible: controlsVisible) {
                Button("Open Year Elapsed", systemImage: "chart.bar.fill") {
                    DashboardNavigation.shared.open(.yearProgress)
                }
                Divider()
                Button("Hide from desktop", systemImage: "eye.slash", action: hide)
            }
            .padding(12)

        }
        .onHover { controlsVisible = $0 }
    }

}

struct YearProgressGrid: View {
    let year: Int
    let now: Date
    let compactCrosses: Bool

    init(year: Int, now: Date, compactCrosses: Bool = false) {
        self.year = year
        self.now = now
        self.compactCrosses = compactCrosses
    }

    var body: some View {
        GeometryReader { proxy in
            let days = daysInYear
            let spacing: CGFloat = compactCrosses ? 0.75 : 2
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
                    dayCell(date, size: layout.cell)
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

    private func dayCell(_ date: Date, size: CGFloat) -> some View {
        let calendar = TrackerCalendar.calendar
        let today = calendar.startOfDay(for: now)
        let isPast = date < today
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let corner = max(1, size * 0.22)

        return ZStack {
            if isPast {
                Path { path in
                    let inset = compactCrosses ? size * 0.08 : max(0.7, size * 0.18)
                    path.move(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: size - inset, y: size - inset))
                    path.move(to: CGPoint(x: size - inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: size - inset))
                }
                .stroke(Color.indigo.opacity(compactCrosses ? 0.78 : 1), style: StrokeStyle(lineWidth: max(0.75, size * (compactCrosses ? 0.10 : 0.12)), lineCap: .round))
            } else {
                RoundedRectangle(cornerRadius: corner)
                    .fill(isToday ? Color.indigo.opacity(0.24) : Color.secondary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: corner)
                            .strokeBorder(isToday ? Color.indigo : Color.secondary.opacity(0.12), lineWidth: isToday ? 1.5 : 0.7)
                    }
            }
        }
        .frame(width: size, height: size)
    }
}
