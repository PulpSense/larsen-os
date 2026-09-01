import SwiftUI

struct YearTrackerView: View {
    @ObservedObject var store: WallStore
    @State private var displayedYear = Calendar.current.component(.year, from: Date())
    @State private var editingDate = Date()

    private let calendar = TrackerCalendar.calendar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                stats
                historyEditor
                contributionGrid
                legend
            }
            .padding(28)
        }
        .navigationTitle("Consistency")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A year of showing up")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("One square is enough. Click any day up to today to correct your history.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Desktop panel", systemImage: "rectangle.on.rectangle") {
                ConsistencyDesktopPanelController.shared.present(store: store)
            }
            .buttonStyle(.bordered)

            Button("Year progress", systemImage: "chart.bar.fill") {
                YearProgressDesktopPanelController.shared.present()
            }
            .buttonStyle(.bordered)

            HStack(spacing: 4) {
                Button { displayedYear -= 1 } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous year")
                Text(String(displayedYear))
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 58)
                Button { displayedYear += 1 } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(displayedYear >= calendar.component(.year, from: Date()))
                .help("Next year")
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: displayedYear) { _, _ in
            editingDate = editableDateRange.upperBound
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(completedInYear)", label: "days completed", icon: "checkmark")
            StatCard(value: "\(currentStreak)", label: "day streak", icon: "flame.fill")
            StatCard(value: completionPercent, label: "of elapsed days", icon: "chart.line.uptrend.xyaxis")
        }
    }

    private var contributionGrid: some View {
        GeometryReader { proxy in
            let weeks = TrackerCalendar.weeks(in: displayedYear)
            let spacing: CGFloat = 3
            let cell = min(15, max(9, (proxy.size.width - CGFloat(weeks.count - 1) * spacing) / CGFloat(weeks.count)))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        Text(TrackerCalendar.monthLabel(for: week))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: cell, alignment: .leading)
                    }
                }

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { weekday in
                                if let date = week[weekday] {
                                    dayCell(date, size: cell)
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(22)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20))
        }
        .frame(height: 190)
    }

    private var historyEditor: some View {
        HStack(spacing: 12) {
            Label("Edit a previous day", systemImage: "calendar.badge.checkmark")
                .font(.headline)

            DatePicker(
                "Day",
                selection: $editingDate,
                in: editableDateRange,
                displayedComponents: .date
            )
            .labelsHidden()

            Button(store.isCompleted(editingDate) ? "Unmark day" : "Mark complete") {
                store.toggle(editingDate)
            }
            .buttonStyle(.borderedProminent)

            Text(store.isCompleted(editingDate) ? "Completed" : "Not marked")
                .font(.caption.weight(.medium))
                .foregroundStyle(store.isCompleted(editingDate) ? .green : .secondary)

            Spacer()
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayCell(_ date: Date, size: CGFloat) -> some View {
        let complete = store.isCompleted(date)
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()

        return Button {
            store.toggle(date)
        } label: {
            RoundedRectangle(cornerRadius: max(2.5, size * 0.23), style: .continuous)
                .fill(complete ? Color.indigo : Color.secondary.opacity(isFuture ? 0.08 : 0.18))
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: max(2.5, size * 0.23), style: .continuous)
                            .stroke(Color.primary.opacity(0.8), lineWidth: 1.5)
                    }
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .help(date.formatted(date: .complete, time: .omitted) + (complete ? " — complete" : ""))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.18)).frame(width: 13, height: 13)
            Text("Not marked")
            RoundedRectangle(cornerRadius: 3).fill(.indigo).frame(width: 13, height: 13)
            Text("Completed")
            Spacer()
            if displayedYear == calendar.component(.year, from: Date()) {
                Button("Toggle today") { store.toggle(Date()) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var completedInYear: Int {
        store.completedDays.filter { $0.hasPrefix("\(displayedYear)-") }.count
    }

    private var editableDateRange: ClosedRange<Date> {
        let start = calendar.date(from: DateComponents(year: displayedYear, month: 1, day: 1))
            ?? Date()
        let nextYear = calendar.date(from: DateComponents(year: displayedYear + 1, month: 1, day: 1))
            ?? Date()
        let endOfYear = calendar.date(byAdding: .second, value: -1, to: nextYear) ?? nextYear
        return start...min(Date(), endOfYear)
    }

    private var elapsedDays: Int {
        guard let start = calendar.date(from: DateComponents(year: displayedYear, month: 1, day: 1)),
              let endOfYear = calendar.date(from: DateComponents(year: displayedYear + 1, month: 1, day: 1)) else { return 1 }
        let end = min(Date(), endOfYear)
        return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    private var completionPercent: String {
        "\(Int((Double(completedInYear) / Double(elapsedDays) * 100).rounded()))%"
    }

    private var currentStreak: Int {
        var date = Date()
        var streak = 0
        while store.isCompleted(date) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return streak
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 34, height: 34)
                .background(.indigo.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.bold()).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

enum TrackerCalendar {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.firstWeekday = 2
        return calendar
    }()

    static func weeks(in year: Int) -> [[Date?]] {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return [] }

        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 365
        let totalSlots = Int(ceil(Double(leading + dayCount) / 7.0)) * 7
        let slots: [Date?] = (0..<totalSlots).map { index in
            let dayOffset = index - leading
            guard dayOffset >= 0 && dayOffset < dayCount else { return nil }
            return calendar.date(byAdding: .day, value: dayOffset, to: start)
        }
        return stride(from: 0, to: slots.count, by: 7).map {
            Array(slots[$0..<min($0 + 7, slots.count)])
        }
    }

    static func monthLabel(for week: [Date?]) -> String {
        guard let date = week.compactMap({ $0 }).first(where: { calendar.component(.day, from: $0) == 1 }) else {
            return ""
        }
        return date.formatted(.dateTime.month(.abbreviated))
    }
}
