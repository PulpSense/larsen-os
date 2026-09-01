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

struct ToggleTodayV3Intent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Today's Work"
    static let description = IntentDescription("Marks or unmarks today in Digital Wall.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let state = WidgetContent.toggling(Date(), in: WallPersistence.load())
        try WallPersistence.save(state)
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfiguration.consistencyWidgetKind)
        return .result()
    }
}
