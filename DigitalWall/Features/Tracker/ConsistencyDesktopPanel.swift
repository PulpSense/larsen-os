import AppKit
import SwiftUI

@MainActor
final class ConsistencyDesktopPanelController {
    static let shared = ConsistencyDesktopPanelController()

    private let enabledKey = "desktopConsistencyPanelEnabled"
    private var panel: DesktopWallPanel?

    private init() {}

    func restoreIfEnabled(store: WallStore) {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey)
        if enabled { present(store: store) }
    }

    func present(store: WallStore) {
        UserDefaults.standard.set(true, forKey: enabledKey)

        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 680, height: 300),
            minimumSize: NSSize(width: 460, height: 220),
            frameAutosaveName: "DigitalWallConsistencyDesktopPanel",
            defaultOffset: NSPoint(x: 500, y: 36)
        ) {
            ConsistencyDesktopPanelContent(
                store: store,
                close: { [weak self] in
                    self?.dismiss()
                }
            )
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

private struct ConsistencyDesktopPanelContent: View {
    @ObservedObject var store: WallStore
    let close: () -> Void
    @State private var controlsVisible = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        let year = TrackerCalendar.calendar.component(.year, from: now)
        let wonDays = store.completedDays.filter { $0.hasPrefix("\(year)-") }.count
        let todayHours = store.deepWorkHours(on: now)
        let todayComplete = store.isCompleted(now)

        return ZStack(alignment: .topTrailing) {
            DesktopPanelBackground()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Deep Work Hours")
                            .font(.headline)
                            .foregroundStyle(.indigo)
                        Text(todayComplete ? "\(todayHours) h today · day won" : "\(todayHours) / 4 h today")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }

                    Spacer()

                    Button {
                        addHour(now: now)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(todayComplete ? Color.green : Color.indigo, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help("Log one deep work hour")

                    DesktopPanelControlMenu(isVisible: controlsVisible) {
                        Button("Close", systemImage: "xmark", role: .destructive, action: close)
                    }
                }

                DesktopConsistencyYearGrid(
                    year: year,
                    hoursByDay: store.deepWorkHours,
                    now: now
                )
                .frame(maxHeight: .infinity)

                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                        Text("\(currentStreak(now: now)) \(currentStreak(now: now) == 1 ? "day" : "days") streak")
                    }
                    .foregroundStyle(Color.digitalWallFlame)
                    Spacer()
                    Text("\(year) · \(wonDays) won \(wonDays == 1 ? "day" : "days")")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(18)

        }
        .onHover { controlsVisible = $0 }
    }

    private func currentStreak(now: Date) -> Int {
        ConsistencyStreak.current(
            completedDays: store.completedDays,
            through: now,
            calendar: TrackerCalendar.calendar
        )
    }

    private func addHour(now: Date) {
        _ = store.addDeepWorkHour(on: now)
        let hours = store.deepWorkHours(on: now)
        guard hours >= DeepWork.dailyGoalHours else { return }
        DeepWorkCelebrationPresenter.shared.present(
            hours: hours,
            streak: currentStreak(now: now),
            hideApplicationOnDismiss: false
        )
    }
}

private struct DesktopConsistencyYearGrid: View {
    let year: Int
    let hoursByDay: [String: Int]
    let now: Date

    var body: some View {
        GeometryReader { proxy in
            let weeks = TrackerCalendar.weeks(in: year)
            let spacing: CGFloat = 2
            let monthHeight: CGFloat = 12
            let monthSpacing: CGFloat = 3
            let cellWidth = max(
                1,
                (proxy.size.width - CGFloat(weeks.count - 1) * spacing) / CGFloat(weeks.count)
            )
            let gridHeight = max(1, proxy.size.height - monthHeight - monthSpacing)
            let cellHeight = max(1, (gridHeight - CGFloat(6) * spacing) / 7)
            let cell = min(cellWidth, cellHeight)

            VStack(alignment: .leading, spacing: monthSpacing) {
                HStack(spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        Text(TrackerCalendar.monthLabel(for: week))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: cell, height: monthHeight, alignment: .leading)
                    }
                }

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { weekday in
                                if let date = week[weekday] {
                                    RoundedRectangle(cornerRadius: max(1, cell * 0.22))
                                        .fill(color(for: date))
                                        .overlay {
                                            if TrackerCalendar.calendar.isDate(date, inSameDayAs: now) {
                                                RoundedRectangle(cornerRadius: max(1, cell * 0.22))
                                                    .stroke(.primary.opacity(0.72), lineWidth: 1)
                                            }
                                        }
                                        .frame(width: cell, height: cell)
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func color(for date: Date) -> Color {
        if date > now { return .secondary.opacity(0.06) }
        return DeepWorkVisuals.color(for: hoursByDay[DayKey.string(from: date), default: 0])
    }
}
