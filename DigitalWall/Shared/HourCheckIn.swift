import Foundation

struct WebhookSettings: Codable, Equatable, Sendable {
    var url = ""
    var isEnabled = false
}

enum HourCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case sales = "Sales", marketing = "Marketing", fulfillment = "Fulfillment"
    case operations = "Operations", learning = "Learning", other = "Other"
    var id: Self { self }
}

struct DailyPreparation: Codable, Equatable, Sendable {
    var read10XRule = false
    var reviewedTopGoals = false
    var reviewedVersionOfMyself = false
    var readMotivationListOutLoud = false
    var readThoughtHabits = false
    var reviewedVisionBoard = false

    enum CodingKeys: String, CodingKey {
        case read10XRule = "read_10x_rule", reviewedTopGoals = "reviewed_top_goals"
        case reviewedVersionOfMyself = "reviewed_version_of_myself"
        case readMotivationListOutLoud = "read_motivation_list_out_loud"
        case readThoughtHabits = "read_thought_habits", reviewedVisionBoard = "reviewed_vision_board"
    }
}

struct HourCheckInForm: Codable, Equatable, Sendable {
    var date = Date()
    var category: HourCategory?
    var isDeepWork = false
    var activity = ""
    var distractions = ""
    var preparation = DailyPreparation()

    var validationMessage: String? {
        if category == nil { return "Select a category." }
        if activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Describe what you did during this hour."
        }
        if distractions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Describe your distractions, or enter none."
        }
        return nil
    }
}

struct HourCheckIn: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let completedAt: Date
    let day: String
    let timeZone: String
    let summary: String
    let notes: String
    let hoursAfter: Int
    var form: HourCheckInForm?
    var deliveredAt: Date?
    var attempts = 0
    var nextAttemptAt: Date?
    var lastDeliveryError: String?

    var payload: CheckInPayload {
        CheckInPayload(
            submissionID: id, event: "hour.completed", completedAt: completedAt,
            day: day, timeZone: timeZone, summary: summary, notes: notes,
            hours: form?.isDeepWork == false ? 0 : 1, dailyHours: hoursAfter,
            category: form?.category?.rawValue, isDeepWork: form?.isDeepWork ?? true,
            distractions: form?.distractions, dailyPreparation: form?.preparation,
            activity: form?.activity
        )
    }

    mutating func recordFailure(_ message: String, at date: Date) {
        attempts += 1
        lastDeliveryError = message
        nextAttemptAt = date.addingTimeInterval(min(300, 30 * pow(2, Double(min(attempts - 1, 4)))))
    }
}

struct CheckInPayload: Encodable, Sendable {
    let schemaVersion = 2
    let submissionID: UUID
    let event: String
    let completedAt: Date
    let day: String
    let timeZone: String
    let summary: String
    let notes: String
    let hours: Int
    let dailyHours: Int
    var category: String? = nil
    var isDeepWork = true
    var distractions: String? = nil
    var dailyPreparation: DailyPreparation? = nil
    var activity: String? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", submissionID = "submission_id"
        case event, completedAt = "completed_at", day, timeZone = "time_zone"
        case summary, notes, hours, dailyHours = "daily_hours"
        case category, isDeepWork = "is_deep_work", distractions, dailyPreparation = "daily_preparation", activity
    }

    static func test(at date: Date = Date()) -> CheckInPayload {
        CheckInPayload(
            submissionID: UUID(), event: "webhook.test", completedAt: date,
            day: DayKey.string(from: date), timeZone: TimeZone.current.identifier,
            summary: "Digital Wall webhook test", notes: "", hours: 0, dailyHours: 0,
            category: HourCategory.other.rawValue, isDeepWork: false, distractions: "None",
            dailyPreparation: DailyPreparation(), activity: "Digital Wall webhook test"
        )
    }
}

enum HourCheckIns {
    static func recording(id: UUID, form: HourCheckInForm, at date: Date, in state: WallState) -> WallState {
        guard !state.hourCheckIns.contains(where: { $0.id == id }) else { return state }
        var form = form
        form.activity = form.activity.trimmingCharacters(in: .whitespacesAndNewlines)
        form.distractions = form.distractions.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = form.isDeepWork ? DeepWork.addingHour(on: form.date, to: state) : state
        updated.hourCheckIns.append(HourCheckIn(
            id: id, completedAt: date, day: DayKey.string(from: form.date),
            timeZone: TimeZone.current.identifier, summary: form.activity, notes: "",
            hoursAfter: DeepWork.hours(on: form.date, in: updated.deepWorkHours), form: form
        ))
        return updated
    }

    // The check-in and the hour share the same atomic state-file write.
    static func recording(
        id: UUID, summary: String, notes: String, at date: Date, in state: WallState
    ) -> WallState {
        guard !state.hourCheckIns.contains(where: { $0.id == id }) else { return state }
        var updated = DeepWork.addingHour(on: date, to: state)
        updated.hourCheckIns.append(HourCheckIn(
            id: id, completedAt: date, day: DayKey.string(from: date),
            timeZone: TimeZone.current.identifier,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            hoursAfter: DeepWork.hours(on: date, in: updated.deepWorkHours)
        ))
        return updated
    }
}
