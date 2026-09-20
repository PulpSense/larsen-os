import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WallStore: ObservableObject {
    @Published private(set) var state: WallState
    @Published var lastError: String?

    init() {
        state = WallPersistence.load()
        removeLegacyFolderAccess()
    }

    var images: [VisionImage] { state.images }
    var visionBoards: [VisionBoard] { state.visionBoards }
    var visionBoardPrivacyEnabled: Bool { state.visionBoardPrivacyEnabled }
    var visionBoardPrivacyMessage: String { state.visionBoardPrivacyMessage }
    var completedDays: Set<String> { state.completedDays }
    var deepWorkHours: [String: Int] { state.deepWorkHours }
    var worldClocks: [WorldClock] { state.worldClocks }
    var desktopPhrases: [DesktopPhrase] { state.desktopPhrases }

    func visionBoard(_ id: UUID) -> VisionBoard? {
        state.visionBoards.first { $0.id == id }
    }

    func images(for boardID: UUID) -> [VisionImage] {
        guard let board = visionBoard(boardID) else { return [] }
        let imagesByID = Dictionary(uniqueKeysWithValues: state.images.map { ($0.id, $0) })
        return board.imageIDs.compactMap { imagesByID[$0] }
    }

    func desktopPreviewImages(for boardID: UUID) -> [VisionImage] {
        guard !state.visionBoardPrivacyEnabled,
              let board = visionBoard(boardID) else { return [] }
        return images(for: boardID).filter { !board.hiddenDesktopImageIDs.contains($0.id) }
    }

    @discardableResult
    func addVisionBoard() -> UUID {
        let board = VisionBoard(name: "New vision board")
        state.visionBoards.append(board)
        persist()
        return board.id
    }

    func updateVisionBoardName(_ id: UUID, name: String) {
        guard let index = state.visionBoards.firstIndex(where: { $0.id == id }) else { return }
        state.visionBoards[index].name = name
        persist()
    }

    func setVisionBoardVisibility(_ id: UUID, isVisible: Bool) {
        guard let index = state.visionBoards.firstIndex(where: { $0.id == id }) else { return }
        guard state.visionBoards[index].isVisible != isVisible else { return }
        state.visionBoards[index].isVisible = isVisible
        persist()
    }

    func setVisionBoardPrivacy(enabled: Bool) {
        guard state.visionBoardPrivacyEnabled != enabled else { return }
        state.visionBoardPrivacyEnabled = enabled
        persist()
    }

    func setVisionBoardPrivacyMessage(_ message: String) {
        state.visionBoardPrivacyMessage = message
        persist()
    }

    func setImageHiddenOnDesktop(_ imageID: UUID, boardID: UUID, hidden: Bool) {
        guard let index = state.visionBoards.firstIndex(where: { $0.id == boardID }) else { return }
        if hidden {
            state.visionBoards[index].hiddenDesktopImageIDs.insert(imageID)
        } else {
            state.visionBoards[index].hiddenDesktopImageIDs.remove(imageID)
        }
        persist()
    }

    var phrasesMarkdown: String {
        get { state.desktopPhrases.first?.markdown ?? state.phrasesMarkdown }
        set {
            state.phrasesMarkdown = newValue
            if state.desktopPhrases.isEmpty {
                state.desktopPhrases = [
                    DesktopPhrase(id: DesktopPhrase.primaryID, markdown: newValue)
                ]
            } else {
                state.desktopPhrases[0].markdown = newValue
            }
            persist()
        }
    }

    func desktopPhrase(_ id: UUID) -> DesktopPhrase? {
        state.desktopPhrases.first { $0.id == id }
    }

    @discardableResult
    func addDesktopPhrase() -> UUID {
        let phrase = DesktopPhrase(
            markdown: "## New phrase\n\nWrite something worth returning to."
        )
        state.desktopPhrases.append(phrase)
        persist()
        return phrase.id
    }

    func updateDesktopPhrase(_ id: UUID, markdown: String) {
        guard let index = state.desktopPhrases.firstIndex(where: { $0.id == id }) else { return }
        state.desktopPhrases[index].markdown = markdown
        if index == 0 { state.phrasesMarkdown = markdown }
        persist()
    }

    func setDesktopPhraseVisibility(_ id: UUID, isVisible: Bool) {
        guard let index = state.desktopPhrases.firstIndex(where: { $0.id == id }) else { return }
        guard state.desktopPhrases[index].isVisible != isVisible else { return }
        state.desktopPhrases[index].isVisible = isVisible
        persist()
    }

    func removeDesktopPhrase(_ id: UUID) {
        guard state.desktopPhrases.count > 1 else { return }
        state.desktopPhrases.removeAll { $0.id == id }
        state.phrasesMarkdown = state.desktopPhrases[0].markdown
        persist()
    }

    func isCompleted(_ date: Date) -> Bool {
        DeepWork.isWon(date, in: state.deepWorkHours)
    }

    func deepWorkHours(on date: Date) -> Int {
        DeepWork.hours(on: date, in: state.deepWorkHours)
    }

    @discardableResult
    func addDeepWorkHour(on date: Date) -> Bool {
        state.deepWorkHours = WallPersistence.load().deepWorkHours
        let previousHours = deepWorkHours(on: date)
        state = DeepWork.addingHour(on: date, to: state)
        persist(preserveOnDiskDeepWorkHours: false)
        return previousHours == DeepWork.dailyGoalHours - 1
    }

    func setDeepWorkHours(_ hours: Int, on date: Date) {
        state.deepWorkHours = WallPersistence.load().deepWorkHours
        state = DeepWork.settingHours(hours, on: date, in: state)
        persist(preserveOnDiskDeepWorkHours: false)
    }

    func reloadFromDisk() {
        state = WallPersistence.load()
    }

    func updatePhrase(_ phrase: String, for id: UUID) {
        guard let index = state.images.firstIndex(where: { $0.id == id }) else { return }
        state.images[index].phrase = phrase
        persist()
    }

    func removeImage(_ image: VisionImage) {
        state.images.removeAll { $0.id == image.id }
        for index in state.visionBoards.indices {
            state.visionBoards[index].imageIDs.removeAll { $0 == image.id }
            state.visionBoards[index].hiddenDesktopImageIDs.remove(image.id)
        }
        try? FileManager.default.removeItem(at: WallPersistence.imageURL(for: image))
        persist()
    }

    func removeImage(_ image: VisionImage, from boardID: UUID) {
        guard let boardIndex = state.visionBoards.firstIndex(where: { $0.id == boardID }) else { return }
        state.visionBoards[boardIndex].imageIDs.removeAll { $0 == image.id }
        state.visionBoards[boardIndex].hiddenDesktopImageIDs.remove(image.id)
        let usedElsewhere = state.visionBoards.contains { $0.imageIDs.contains(image.id) }
        if !usedElsewhere {
            state.images.removeAll { $0.id == image.id }
            try? FileManager.default.removeItem(at: WallPersistence.imageURL(for: image))
        }
        persist()
    }

    func removeVisionBoard(_ id: UUID) {
        guard state.visionBoards.count > 1,
              let board = visionBoard(id) else { return }
        state.visionBoards.removeAll { $0.id == id }
        let remainingIDs = Set(state.visionBoards.flatMap(\.imageIDs))
        for imageID in board.imageIDs where !remainingIDs.contains(imageID) {
            if let image = state.images.first(where: { $0.id == imageID }) {
                try? FileManager.default.removeItem(at: WallPersistence.imageURL(for: image))
            }
            state.images.removeAll { $0.id == imageID }
        }
        persist()
    }

    func importImages(from urls: [URL], to boardID: UUID? = nil) {
        do {
            try FileManager.default.createDirectory(
                at: AppConfiguration.imagesDirectoryURL,
                withIntermediateDirectories: true
            )

            var importedIDs: [UUID] = []
            for sourceURL in urls {
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let values = try sourceURL.resourceValues(forKeys: [.contentTypeKey])
                guard values.contentType?.conforms(to: .image) == true else { continue }

                let id = UUID()
                let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
                let fileName = "\(id.uuidString).\(ext)"
                let destination = AppConfiguration.imagesDirectoryURL.appendingPathComponent(fileName)
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                state.images.append(VisionImage(id: id, fileName: fileName))
                importedIDs.append(id)
            }
            let targetID = boardID ?? state.visionBoards.first?.id
            if let targetID,
               let boardIndex = state.visionBoards.firstIndex(where: { $0.id == targetID }) {
                state.visionBoards[boardIndex].imageIDs.append(contentsOf: importedIDs)
            }
            persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addWorldClock() {
        let used = Set(state.worldClocks.map(\.timeZoneIdentifier))
        let identifier = TimeZone.knownTimeZoneIdentifiers.first { !used.contains($0) }
            ?? TimeZone.current.identifier
        state.worldClocks.append(
            WorldClock(name: WorldClockFormatting.cityName(for: identifier), timeZoneIdentifier: identifier)
        )
        persist()
    }

    func updateWorldClock(_ id: UUID, name: String? = nil, timeZoneIdentifier: String? = nil) {
        guard let index = state.worldClocks.firstIndex(where: { $0.id == id }) else { return }
        if let name { state.worldClocks[index].name = name }
        if let timeZoneIdentifier { state.worldClocks[index].timeZoneIdentifier = timeZoneIdentifier }
        persist()
    }

    func removeWorldClock(_ id: UUID) {
        state.worldClocks.removeAll { $0.id == id }
        persist()
    }

    func moveWorldClock(
        _ sourceID: UUID,
        relativeTo destinationID: UUID,
        placeAfterDestination: Bool
    ) {
        let reordered = WorldClockOrdering.moving(
            sourceID,
            before: destinationID,
            placeAfterDestination: placeAfterDestination,
            in: state.worldClocks
        )
        guard reordered != state.worldClocks else { return }
        state.worldClocks = reordered
        persist()
    }

    private func removeLegacyFolderAccess() {
        let manager = FileManager.default
        let cachedFiles = (try? manager.contentsOfDirectory(
            at: AppConfiguration.imagesDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in cachedFiles where file.lastPathComponent.hasPrefix("folder-") {
            try? manager.removeItem(at: file)
        }

        guard !state.folders.isEmpty else { return }
        state.folders.removeAll()
        try? WallPersistence.save(state)
    }

    private func persist(preserveOnDiskDeepWorkHours: Bool = true) {
        do {
            if preserveOnDiskDeepWorkHours {
                state.deepWorkHours = WallPersistence.load().deepWorkHours
            }
            try WallPersistence.save(state)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
