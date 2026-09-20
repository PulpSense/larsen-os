import Foundation

struct VisionImage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var fileName: String
    var phrase: String

    init(id: UUID = UUID(), fileName: String, phrase: String = "") {
        self.id = id
        self.fileName = fileName
        self.phrase = phrase
    }
}

struct VisionBoard: Codable, Identifiable, Hashable, Sendable {
    static let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    let id: UUID
    var name: String
    var imageIDs: [UUID]
    var hiddenDesktopImageIDs: Set<UUID>
    var isVisible: Bool

    init(
        id: UUID = UUID(),
        name: String,
        imageIDs: [UUID] = [],
        hiddenDesktopImageIDs: Set<UUID> = [],
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.imageIDs = imageIDs
        self.hiddenDesktopImageIDs = hiddenDesktopImageIDs
        self.isVisible = isVisible
    }
}

struct VisionFolder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var bookmarkData: Data
    var cacheKey: String

    init(id: UUID = UUID(), name: String, bookmarkData: Data, cacheKey: String) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.cacheKey = cacheKey
    }
}

struct WorldClock: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var timeZoneIdentifier: String

    init(id: UUID = UUID(), name: String, timeZoneIdentifier: String) {
        self.id = id
        self.name = name
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

struct DesktopPhrase: Codable, Identifiable, Hashable, Sendable {
    static let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    let id: UUID
    var markdown: String
    var isVisible: Bool

    init(id: UUID = UUID(), markdown: String, isVisible: Bool = true) {
        self.id = id
        self.markdown = markdown
        self.isVisible = isVisible
    }
}

struct WallState: Codable, Sendable {
    var images: [VisionImage]
    var visionBoards: [VisionBoard]
    var visionBoardPrivacyEnabled: Bool
    var visionBoardPrivacyMessage: String
    var folders: [VisionFolder]
    var deepWorkHours: [String: Int]
    var phrasesMarkdown: String
    var desktopPhrases: [DesktopPhrase]
    var worldClocks: [WorldClock]

    init(
        images: [VisionImage],
        visionBoards: [VisionBoard]? = nil,
        visionBoardPrivacyEnabled: Bool = false,
        visionBoardPrivacyMessage: String = "Private vision board",
        folders: [VisionFolder] = [],
        completedDays: Set<String>,
        deepWorkHours: [String: Int]? = nil,
        phrasesMarkdown: String,
        desktopPhrases: [DesktopPhrase]? = nil,
        worldClocks: [WorldClock] = WallState.starterWorldClocks
    ) {
        self.images = images
        self.visionBoards = visionBoards ?? [
            VisionBoard(
                id: VisionBoard.primaryID,
                name: "Vision board",
                imageIDs: images.map(\.id)
            )
        ]
        self.visionBoardPrivacyEnabled = visionBoardPrivacyEnabled
        self.visionBoardPrivacyMessage = visionBoardPrivacyMessage
        self.folders = folders
        self.deepWorkHours = Self.sanitizedDeepWorkHours(
            deepWorkHours ?? Dictionary(uniqueKeysWithValues: completedDays.map {
                ($0, DeepWork.dailyGoalHours)
            })
        )
        self.phrasesMarkdown = phrasesMarkdown
        self.desktopPhrases = desktopPhrases ?? [
            DesktopPhrase(id: DesktopPhrase.primaryID, markdown: phrasesMarkdown)
        ]
        self.worldClocks = worldClocks
    }

    private enum CodingKeys: String, CodingKey {
        case images, visionBoards, visionBoardPrivacyEnabled, visionBoardPrivacyMessage
        case folders, completedDays, deepWorkHours, phrasesMarkdown, desktopPhrases, worldClocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        images = try container.decodeIfPresent([VisionImage].self, forKey: .images) ?? []
        visionBoards = try container.decodeIfPresent([VisionBoard].self, forKey: .visionBoards) ?? [
            VisionBoard(
                id: VisionBoard.primaryID,
                name: "Vision board",
                imageIDs: images.map(\.id)
            )
        ]
        if visionBoards.isEmpty {
            visionBoards = [VisionBoard(id: VisionBoard.primaryID, name: "Vision board")]
        }
        visionBoardPrivacyEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .visionBoardPrivacyEnabled
        ) ?? false
        visionBoardPrivacyMessage = try container.decodeIfPresent(
            String.self,
            forKey: .visionBoardPrivacyMessage
        ) ?? "Private vision board"
        folders = try container.decodeIfPresent([VisionFolder].self, forKey: .folders) ?? []
        if let savedHours = try container.decodeIfPresent([String: Int].self, forKey: .deepWorkHours) {
            deepWorkHours = Self.sanitizedDeepWorkHours(savedHours)
        } else {
            let completedDays = try container.decodeIfPresent(Set<String>.self, forKey: .completedDays) ?? []
            deepWorkHours = Dictionary(uniqueKeysWithValues: completedDays.map {
                ($0, DeepWork.dailyGoalHours)
            })
        }
        phrasesMarkdown = try container.decodeIfPresent(String.self, forKey: .phrasesMarkdown) ?? Self.starterPhrases
        desktopPhrases = try container.decodeIfPresent([DesktopPhrase].self, forKey: .desktopPhrases) ?? [
            DesktopPhrase(id: DesktopPhrase.primaryID, markdown: phrasesMarkdown)
        ]
        if desktopPhrases.isEmpty {
            desktopPhrases = [DesktopPhrase(id: DesktopPhrase.primaryID, markdown: phrasesMarkdown)]
        }
        phrasesMarkdown = desktopPhrases[0].markdown
        worldClocks = try container.decodeIfPresent([WorldClock].self, forKey: .worldClocks) ?? Self.starterWorldClocks
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(images, forKey: .images)
        try container.encode(visionBoards, forKey: .visionBoards)
        try container.encode(visionBoardPrivacyEnabled, forKey: .visionBoardPrivacyEnabled)
        try container.encode(visionBoardPrivacyMessage, forKey: .visionBoardPrivacyMessage)
        try container.encode(folders, forKey: .folders)
        try container.encode(completedDays, forKey: .completedDays)
        try container.encode(deepWorkHours, forKey: .deepWorkHours)
        try container.encode(phrasesMarkdown, forKey: .phrasesMarkdown)
        try container.encode(desktopPhrases, forKey: .desktopPhrases)
        try container.encode(worldClocks, forKey: .worldClocks)
    }

    var completedDays: Set<String> {
        Set(deepWorkHours.compactMap { day, hours in
            hours >= DeepWork.dailyGoalHours ? day : nil
        })
    }

    private static func sanitizedDeepWorkHours(_ hours: [String: Int]) -> [String: Int] {
        hours.reduce(into: [:]) { result, entry in
            if entry.value > 0 { result[entry.key] = entry.value }
        }
    }

    static let starterPhrases = """
    ## Keep going

    - Build the life you want to wake up to.
    - Small steps, repeated, become a body of work.
    - Protect your attention.
    """

    static var starterWorldClocks: [WorldClock] {
        [
            WorldClock(name: "Local", timeZoneIdentifier: TimeZone.current.identifier),
            WorldClock(name: "San Francisco", timeZoneIdentifier: "America/Los_Angeles"),
            WorldClock(name: "New York", timeZoneIdentifier: "America/New_York"),
            WorldClock(name: "London", timeZoneIdentifier: "Europe/London"),
            WorldClock(name: "Budapest", timeZoneIdentifier: "Europe/Budapest"),
            WorldClock(name: "Tokyo", timeZoneIdentifier: "Asia/Tokyo")
        ]
    }

    static let empty = WallState(
        images: [],
        completedDays: [],
        phrasesMarkdown: starterPhrases
    )
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

enum DeepWork {
    static let dailyGoalHours = 4

    static func hours(on date: Date, in hoursByDay: [String: Int]) -> Int {
        hoursByDay[DayKey.string(from: date), default: 0]
    }

    static func isWon(_ date: Date, in hoursByDay: [String: Int]) -> Bool {
        hours(on: date, in: hoursByDay) >= dailyGoalHours
    }

    static func addingHour(on date: Date, to state: WallState) -> WallState {
        var updated = state
        let key = DayKey.string(from: date)
        updated.deepWorkHours[key, default: 0] += 1
        return updated
    }

    static func settingHours(_ hours: Int, on date: Date, in state: WallState) -> WallState {
        var updated = state
        let key = DayKey.string(from: date)
        if hours > 0 {
            updated.deepWorkHours[key] = hours
        } else {
            updated.deepWorkHours.removeValue(forKey: key)
        }
        return updated
    }
}

enum DeepWorkCelebrationMilestone: Equatable {
    case dayWon
    case bonusHour
    case momentum
    case unstoppable
    case doubleGoal
    case keepBuilding

    static func forHours(_ hours: Int) -> DeepWorkCelebrationMilestone? {
        switch hours {
        case 4: .dayWon
        case 5: .bonusHour
        case 6: .momentum
        case 7: .unstoppable
        case 8: .doubleGoal
        case 9...: .keepBuilding
        default: nil
        }
    }

    func configuration(hours: Int) -> DeepWorkCelebrationConfiguration {
        switch self {
        case .dayWon:
            return DeepWorkCelebrationConfiguration(
                title: "DAY WON",
                detail: "4 hours of deep work",
                particleCount: 220
            )
        case .bonusHour:
            return DeepWorkCelebrationConfiguration(
                title: "BONUS HOUR",
                detail: "Every hour beyond four makes you stronger.",
                particleCount: 12
            )
        case .momentum:
            return DeepWorkCelebrationConfiguration(
                title: "MOMENTUM",
                detail: "Extra hours compound.",
                particleCount: 20
            )
        case .unstoppable:
            return DeepWorkCelebrationConfiguration(
                title: "UNSTOPPABLE",
                detail: "Discipline today. A brighter tomorrow.",
                particleCount: 26
            )
        case .doubleGoal:
            return DeepWorkCelebrationConfiguration(
                title: "2× GOAL",
                detail: "Twice the target.",
                particleCount: 42
            )
        case .keepBuilding:
            let cycle = max(0, hours - 9) % 7
            return DeepWorkCelebrationConfiguration(
                title: "KEEP BUILDING",
                detail: "No limits. More focus.",
                particleCount: 28 + cycle * 4
            )
        }
    }
}

struct DeepWorkCelebrationConfiguration: Equatable {
    let title: String
    let detail: String
    let particleCount: Int
}

enum ConsistencyStreak {
    static func current(
        completedDays: Set<String>,
        through date: Date,
        calendar: Calendar = .current
    ) -> Int {
        var cursor = date
        if !completedDays.contains(DayKey.string(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while completedDays.contains(DayKey.string(from: cursor)) {
            streak += 1
            guard let prior = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = prior
        }
        return streak
    }
}

enum WorldClockOrdering {
    static func moving(
        _ sourceID: UUID,
        before destinationID: UUID,
        placeAfterDestination: Bool = false,
        in clocks: [WorldClock]
    ) -> [WorldClock] {
        guard sourceID != destinationID,
              let sourceIndex = clocks.firstIndex(where: { $0.id == sourceID }) else {
            return clocks
        }

        var reordered = clocks
        let clock = reordered.remove(at: sourceIndex)
        guard let destinationIndex = reordered.firstIndex(where: { $0.id == destinationID }) else {
            return clocks
        }
        reordered.insert(
            clock,
            at: destinationIndex + (placeAfterDestination ? 1 : 0)
        )
        return reordered
    }
}
