import Foundation

enum YearProgressVisualization: String, CaseIterable, Identifiable {
    case ring
    case monthCalendar
    case dailyGrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ring: "Progress ring"
        case .monthCalendar: "Month calendar"
        case .dailyGrid: "Original day grid"
        }
    }
}

struct YearProgress {
    let year: Int
    let fractionElapsed: Double
    let daysElapsed: Int
    let daysRemaining: Int

    init(now: Date, calendar: Calendar) {
        year = calendar.component(.year, from: now)
        guard let interval = calendar.dateInterval(of: .year, for: now) else {
            fractionElapsed = 0
            daysElapsed = 0
            daysRemaining = 0
            return
        }

        fractionElapsed = min(max(now.timeIntervalSince(interval.start) / interval.duration, 0), 1)
        let today = calendar.startOfDay(for: now)
        daysElapsed = calendar.dateComponents([.day], from: interval.start, to: today).day ?? 0
        daysRemaining = calendar.dateComponents([.day], from: today, to: interval.end).day ?? 0
    }
}
