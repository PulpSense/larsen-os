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
        .navigationTitle("Deep Work Hours")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Deep Work Hours")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Log focused hours. Four hours wins the day and extends your streak.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Show on Desktop", systemImage: "rectangle.on.rectangle") {
                ConsistencyDesktopPanelController.shared.present(store: store)
            }
            .buttonStyle(.bordered)

            Button("Year Elapsed", systemImage: "chart.bar.fill") {
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
            StatCard(value: "\(totalHoursInYear)", label: "deep work hours", icon: "brain.head.profile.fill")
            StatCard(value: "\(completedInYear)", label: "won days", icon: "checkmark")
            StatCard(
                value: "\(currentStreak)",
                label: "day streak",
                icon: "flame.fill",
                tint: Color.digitalWallFlame
            )
        }
    }

    private var contributionGrid: some View {
        GeometryReader { proxy in
            let weeks = TrackerCalendar.weeks(in: displayedYear)
            let spacing: CGFloat = 3
            let horizontalPadding: CGFloat = 22
            let availableWidth = max(1, proxy.size.width - horizontalPadding * 2)
            let cell = min(
                15,
                max(
                    6,
                    (availableWidth - CGFloat(weeks.count - 1) * spacing)
                        / CGFloat(weeks.count)
                )
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: spacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        Text(TrackerCalendar.monthLabel(for: week))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: cell, height: 14, alignment: .leading)
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
            .frame(width: availableWidth, alignment: .center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 22)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20))
        }
        .frame(height: 190)
    }

    private var historyEditor: some View {
        HStack(spacing: 12) {
            Label("Edit deep work", systemImage: "calendar.badge.clock")
                .font(.headline)

            DatePicker(
                "Day",
                selection: $editingDate,
                in: editableDateRange,
                displayedComponents: .date
            )
            .labelsHidden()

            Button {
                store.setDeepWorkHours(max(0, editingHours - 1), on: editingDate)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .disabled(editingHours == 0)

            Text("\(editingHours) h")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 42)

            Button {
                store.setDeepWorkHours(editingHours + 1, on: editingDate)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)

            Text(store.isCompleted(editingDate) ? "Day won" : progressLabel(for: editingHours))
                .font(.caption.weight(.medium))
                .foregroundStyle(store.isCompleted(editingDate) ? .green : .secondary)

            Spacer()
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayCell(_ date: Date, size: CGFloat) -> some View {
        let complete = store.isCompleted(date)
        let hours = store.deepWorkHours(on: date)
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()

        return Button {
            editingDate = date
        } label: {
            RoundedRectangle(cornerRadius: max(2.5, size * 0.23), style: .continuous)
                .fill(color(for: hours, isFuture: isFuture))
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
        .help(date.formatted(date: .complete, time: .omitted) + " — \(hours) h" + (complete ? " · day won" : ""))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.18)).frame(width: 13, height: 13)
            Text("0 h")
            RoundedRectangle(cornerRadius: 3).fill(.indigo.opacity(0.28)).frame(width: 13, height: 13)
            Text("1 h")
            RoundedRectangle(cornerRadius: 3).fill(.indigo.opacity(0.48)).frame(width: 13, height: 13)
            Text("2 h")
            RoundedRectangle(cornerRadius: 3).fill(.indigo.opacity(0.72)).frame(width: 13, height: 13)
            Text("3 h")
            LinearGradient(
                colors: [4, 6, 8, 10].map(DeepWorkVisuals.earnedColor(for:)),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 72, height: 13)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Text("4 h won → 10+ h")
            Spacer()
            if displayedYear == calendar.component(.year, from: Date()) {
                Button("Log 1 hour") { addHour(on: Date()) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var completedInYear: Int {
        store.completedDays.filter { $0.hasPrefix("\(displayedYear)-") }.count
    }

    private var totalHoursInYear: Int {
        store.deepWorkHours.reduce(into: 0) { total, entry in
            if entry.key.hasPrefix("\(displayedYear)-") { total += entry.value }
        }
    }

    private var editingHours: Int {
        store.deepWorkHours(on: editingDate)
    }

    private var editableDateRange: ClosedRange<Date> {
        let start = calendar.date(from: DateComponents(year: displayedYear, month: 1, day: 1))
            ?? Date()
        let nextYear = calendar.date(from: DateComponents(year: displayedYear + 1, month: 1, day: 1))
            ?? Date()
        let endOfYear = calendar.date(byAdding: .second, value: -1, to: nextYear) ?? nextYear
        return start...min(Date(), endOfYear)
    }

    private var currentStreak: Int {
        ConsistencyStreak.current(
            completedDays: store.completedDays,
            through: Date(),
            calendar: calendar
        )
    }

    private func addHour(on date: Date) {
        guard store.addDeepWorkHour(on: date) else { return }
        DeepWorkCelebrationPresenter.shared.present(
            streak: currentStreak,
            hideApplicationOnDismiss: false
        )
    }

    private func color(for hours: Int, isFuture: Bool) -> Color {
        if isFuture { return .secondary.opacity(0.08) }
        return DeepWorkVisuals.color(for: hours)
    }

    private func progressLabel(for hours: Int) -> String {
        hours == 0 ? "No hours logged" : "\(hours) / 4 h"
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    var tint: Color = .indigo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
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
