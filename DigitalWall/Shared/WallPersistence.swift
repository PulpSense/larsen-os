import AppIntents
import Foundation
import WidgetKit

enum WallPersistence {
    static func load() -> WallState {
        guard let data = try? Data(contentsOf: AppConfiguration.stateFileURL),
              let state = try? JSONDecoder().decode(WallState.self, from: data) else {
            return .empty
        }
        return state
    }

    static func save(_ state: WallState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: AppConfiguration.stateFileURL, options: .atomic)
    }

    static func imageURL(for image: VisionImage) -> URL {
        AppConfiguration.imagesDirectoryURL.appendingPathComponent(image.fileName)
    }
}

struct AddDeepWorkHourIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Deep Work Hour"
    static let description = IntentDescription("Logs one hour of deep work for today.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let state = WidgetContent.addingDeepWorkHour(Date(), in: WallPersistence.load())
        try WallPersistence.save(state)
        DistributedNotificationCenter.default().postNotificationName(
            AppConfiguration.deepWorkHoursDidChangeNotification,
            object: nil,
            deliverImmediately: true
        )
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.consistencyWidgetKind)
        return .result()
    }
}
