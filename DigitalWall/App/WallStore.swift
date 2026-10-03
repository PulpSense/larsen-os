import AppKit
import Foundation
import Network
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WallStore: ObservableObject {
    @Published private(set) var state: WallState
    @Published var lastError: String?
    @Published private(set) var isSyncingWebhook = false
    @Published private(set) var isTestingWebhook = false
    @Published private(set) var isOnline = true
    @Published private(set) var webhookError: String?
    @Published private(set) var webhookTestResult: String?

    private let loadState: () -> WallState
    private let saveState: (WallState) throws -> Void
    private let webhookClient: WebhookClient
    private let readWebhookToken: () throws -> String
    private let writeWebhookToken: (String) throws -> Void
    private let networkMonitor = NWPathMonitor()
    private var retryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(
        load: @escaping () -> WallState = WallPersistence.load,
        save: @escaping (WallState) throws -> Void = WallPersistence.save,
        webhookClient: WebhookClient = WebhookClient(),
        readWebhookToken: @escaping () throws -> String = WebhookSecret.read,
        writeWebhookToken: @escaping (String) throws -> Void = WebhookSecret.write,
        startWebhookSync: Bool = true
    ) {
        loadState = load
        saveState = save
        self.webhookClient = webhookClient
        self.readWebhookToken = readWebhookToken
        self.writeWebhookToken = writeWebhookToken
        state = load()
        if startWebhookSync {
            removeLegacyFolderAccess()
            startSyncing()
        }
    }

    deinit {
        networkMonitor.cancel()
        retryTimer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var hourCheckIns: [HourCheckIn] { state.hourCheckIns }
    var webhookSettings: WebhookSettings { state.webhookSettings }
    var pendingCheckIns: [HourCheckIn] { state.hourCheckIns.filter { $0.deliveredAt == nil } }

    var webhookStatus: String {
        if !webhookSettings.isEnabled {
            return isSyncingWebhook ? "Sync paused · finishing the current request" : "Sync paused · \(pendingCheckIns.count) pending"
        }
        if isSyncingWebhook { return "Sending check-ins…" }
        if !isOnline { return "Offline · check-ins saved locally" }
        if let webhookError { return webhookError }
        if let error = pendingCheckIns.first?.lastDeliveryError { return error }
        return pendingCheckIns.isEmpty ? "All check-ins sent" : "\(pendingCheckIns.count) check-ins pending"
    }

    @discardableResult
    func finishHour(id: UUID, form: HourCheckInForm, at date: Date = Date()) -> Bool {
        if let message = form.validationMessage {
            lastError = message
            return false
        }
        var current = state
        current.deepWorkHours = loadState().deepWorkHours
        let updated = HourCheckIns.recording(id: id, form: form, at: date, in: current)
        guard commitCheckIns(updated, preserveOnDiskHours: false) else { return false }
        Task { await syncWebhook() }
        return true
    }

    @discardableResult
    func finishHour(id: UUID, summary: String, notes: String, at date: Date = Date()) -> Bool {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Add a short summary of your hour."
            return false
        }
        var current = state
        current.deepWorkHours = loadState().deepWorkHours
        let updated = HourCheckIns.recording(id: id, summary: summary, notes: notes, at: date, in: current)
        guard commitCheckIns(updated, preserveOnDiskHours: false) else { return false }
        Task { await syncWebhook() }
        return true
    }

    @discardableResult
    func configureWebhook(url: String, token: String, enabled: Bool) -> Bool {
        guard !isTestingWebhook else { return false }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if enabled || !trimmed.isEmpty { _ = try WebhookRequest.endpoint(trimmed) }
            let previousToken = try readWebhookToken()
            try writeWebhookToken(token)
            var updated = state
            updated.webhookSettings = WebhookSettings(url: trimmed, isEnabled: enabled)
            updated.deepWorkHours = loadState().deepWorkHours
            do { try saveState(updated) } catch {
                try? writeWebhookToken(previousToken)
                throw error
            }
            state = updated
            webhookError = nil
            webhookTestResult = nil
            Task { await syncWebhook(force: true) }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func sendWebhookTest() async {
        guard !isTestingWebhook && !isSyncingWebhook else { return }
        isTestingWebhook = true
        webhookTestResult = nil
        defer { isTestingWebhook = false }
        do {
            try await webhookClient.send(.test(), url: webhookSettings.url, token: readWebhookToken())
            webhookTestResult = "Test delivered. Check your automation for a webhook.test event."
        } catch {
            webhookTestResult = WebhookClient.message(for: error)
        }
    }

    func syncWebhook(force: Bool = false) async {
        guard webhookSettings.isEnabled, !isSyncingWebhook, !isTestingWebhook,
              !pendingCheckIns.isEmpty else { return }
        isSyncingWebhook = true
        webhookError = nil
        defer { isSyncingWebhook = false }
        do {
            while webhookSettings.isEnabled, let checkIn = pendingCheckIns.first {
                if !force, let next = checkIn.nextAttemptAt, next > Date() { break }
                // Settings can change while the preceding request is in flight.
                let url = webhookSettings.url
                let token = try readWebhookToken()
                do {
                    try await webhookClient.send(checkIn.payload, url: url, token: token)
                } catch {
                    let message = WebhookClient.message(for: error)
                    webhookError = message
                    var updated = state
                    if let index = updated.hourCheckIns.firstIndex(where: { $0.id == checkIn.id }) {
                        updated.hourCheckIns[index].recordFailure(message, at: Date())
                        _ = commitCheckIns(updated)
                    }
                    break
                }
                var updated = state
                guard let index = updated.hourCheckIns.firstIndex(where: { $0.id == checkIn.id }) else { break }
                updated.hourCheckIns[index].deliveredAt = Date()
                updated.hourCheckIns[index].lastDeliveryError = nil
                updated.hourCheckIns[index].nextAttemptAt = nil
                guard commitCheckIns(updated) else {
                    webhookError = "Delivered, but couldn’t save its status. Will retry with the same submission ID."
                    break
                }
            }
        } catch {
            webhookError = WebhookClient.message(for: error)
        }
    }

    private func commitCheckIns(_ updated: WallState, preserveOnDiskHours: Bool = true) -> Bool {
        do {
            var updated = updated
            // Other app entry points may have written hours while a request was in flight.
            if preserveOnDiskHours {
                updated.deepWorkHours = loadState().deepWorkHours
            }
            try saveState(updated)
            state = updated
            return true
        } catch {
            lastError = "Couldn’t save the check-in: \(error.localizedDescription)"
            return false
        }
    }

    private func startSyncing() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = path.status == .satisfied
                if self.isOnline { await self.syncWebhook(force: !wasOnline) }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "DigitalWall.webhook-network"))
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.syncWebhook() }
        }
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.syncWebhook(force: true) }
        }
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
        state.deepWorkHours = loadState().deepWorkHours
        let previousHours = deepWorkHours(on: date)
        state = DeepWork.addingHour(on: date, to: state)
        persist(preserveOnDiskDeepWorkHours: false)
        return previousHours == DeepWork.dailyGoalHours - 1
    }

    func setDeepWorkHours(_ hours: Int, on date: Date) {
        state.deepWorkHours = loadState().deepWorkHours
        state = DeepWork.settingHours(hours, on: date, in: state)
        persist(preserveOnDiskDeepWorkHours: false)
    }

    func reloadFromDisk() {
        state = loadState()
    }

    func updatePhrase(_ phrase: String, for id: UUID) {
        guard let index = state.images.firstIndex(where: { $0.id == id }) else { return }
        state.images[index].phrase = phrase
        persist()
    }

    func updateImageDisplayMode(_ displayMode: VisionImageDisplayMode, for id: UUID) {
        guard let index = state.images.firstIndex(where: { $0.id == id }) else { return }
        state.images[index].displayMode = displayMode
        persist()
    }

    func updateImageFocalPoint(_ focalPoint: VisionImageFocalPoint, for id: UUID) {
        guard let index = state.images.firstIndex(where: { $0.id == id }) else { return }
        state.images[index].focalPoint = focalPoint
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
        try? saveState(state)
    }

    private func persist(preserveOnDiskDeepWorkHours: Bool = true) {
        do {
            if preserveOnDiskDeepWorkHours {
                state.deepWorkHours = loadState().deepWorkHours
            }
            try saveState(state)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
