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
            initialSize: NSSize(width: 600, height: 240),
            minimumSize: NSSize(width: 500, height: 200),
            frameAutosaveName: "DigitalWallYearProgressDesktopPanelCompact",
            defaultAnchor: .topLeft,
            defaultOffset: NSPoint(x: 36, y: 310),
            locksAspectRatio: true
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
    @AppStorage("yearProgressVisualization") private var visualization = YearProgressVisualization.ring.rawValue

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
                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Year Elapsed")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 8)

                        if visualization != YearProgressVisualization.ring.rawValue {
                            Text(progress.fractionElapsed, format: .percent.precision(.fractionLength(1)))
                                .font(.title3.bold().monospacedDigit())
                        }
                    }

                    ZStack {
                        Text(String(year))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack {
                            Spacer()
                            Text("\(progress.daysElapsed) of \(progress.daysElapsed + progress.daysRemaining) days")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Group {
                    switch YearProgressVisualization(rawValue: visualization) ?? .ring {
                    case .dailyGrid:
                        YearProgressGrid(year: year, now: now, compactCrosses: true)
                    case .ring:
                        YearProgressRing(fraction: progress.fractionElapsed, daysElapsed: progress.daysElapsed, totalDays: progress.daysElapsed + progress.daysRemaining, compact: true)
                    case .monthCalendar:
                        YearProgressMonthCalendar(year: year, now: now, compact: true)
                    }
                }
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
                    .fill(isToday ? Color.green : Color.secondary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: corner)
                            .strokeBorder(isToday ? Color.white.opacity(0.8) : Color.secondary.opacity(0.12), lineWidth: isToday ? 1.5 : 0.7)
                    }
            }
        }
        .frame(width: size, height: size)
    }
}

struct YearProgressRing: View {
    let fraction: Double
    let daysElapsed: Int
    let totalDays: Int
    var compact = false

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(10, diameter * 0.11)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.14), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: compact ? 1 : 5) {
                    Text(fraction, format: .percent.precision(.fractionLength(1)))
                        .font(.system(size: diameter * (compact ? 0.20 : 0.18), weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if !compact {
                        Text("\(daysElapsed) of \(totalDays) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: diameter - lineWidth, height: diameter - lineWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Year elapsed: \(Int((fraction * 100).rounded())) percent, \(daysElapsed) of \(totalDays) days")
    }
}

struct YearProgressMonthCalendar: View {
    let year: Int
    let now: Date
    var compact = false

    private let monthSpacing: CGFloat = 3
    private let cellSpacing: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let cell = min(
                compact ? 11 : 14,
                max(2, min(
                    (proxy.size.width - monthSpacing * 11 - cellSpacing * 24) / 36,
                    (proxy.size.height - (compact ? 16 : 18) - cellSpacing * 10) / 11
                ))
            )

            HStack(alignment: .top, spacing: monthSpacing) {
                ForEach(1...12, id: \.self) { month in
                    monthColumn(month, cell: cell)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(year) month calendar")
    }

    private func monthColumn(_ month: Int, cell: CGFloat) -> some View {
        let calendar = TrackerCalendar.calendar
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
        let columns = Array(repeating: GridItem(.fixed(cell), spacing: cellSpacing), count: 3)

        return VStack(alignment: .center, spacing: compact ? 3 : 5) {
            Text(start.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: compact ? 11 : 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: cell * 3 + cellSpacing * 2, alignment: .center)

            LazyVGrid(columns: columns, spacing: cellSpacing) {
                ForEach(0..<33, id: \.self) { index in
                    if index < count, let date = calendar.date(byAdding: .day, value: index, to: start) {
                        dayCell(date, size: cell)
                    } else {
                        Color.clear.frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date, size: CGFloat) -> some View {
        let calendar = TrackerCalendar.calendar
        let isPast = date < calendar.startOfDay(for: now)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let shape = RoundedRectangle(cornerRadius: max(1, size * 0.2))

        return shape
            .fill(isPast ? Color.indigo : (isToday ? Color.green : Color.secondary.opacity(0.12)))
            .overlay {
                if isToday {
                    shape.strokeBorder(Color.white.opacity(0.8), lineWidth: max(1, size * 0.18))
                }
            }
            .frame(width: size, height: size)
            .help(date.formatted(date: .complete, time: .omitted))
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
