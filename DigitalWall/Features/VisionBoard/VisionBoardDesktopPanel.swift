import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class VisionBoardDesktopPanelController {
    static let shared = VisionBoardDesktopPanelController()

    private let legacyEnabledKey = "desktopVisionBoardEnabled"
    private var panels: [UUID: DesktopWallPanel] = [:]

    private init() {}

    func restoreIfEnabled(store: WallStore) {
        let defaults = UserDefaults.standard
        let primaryEnabled = defaults.object(forKey: legacyEnabledKey) == nil
            || defaults.bool(forKey: legacyEnabledKey)
        for board in store.visionBoards where board.isVisible {
            if board.id == VisionBoard.primaryID && !primaryEnabled { continue }
            present(boardID: board.id, store: store, updateVisibility: false)
        }
    }

    func present(store: WallStore) {
        guard let boardID = DashboardNavigation.shared.boardID(in: store) else { return }
        present(boardID: boardID, store: store)
    }

    func present(
        boardID: UUID,
        store: WallStore,
        updateVisibility: Bool = true
    ) {
        guard store.visionBoard(boardID) != nil else { return }
        if boardID == VisionBoard.primaryID {
            UserDefaults.standard.set(true, forKey: legacyEnabledKey)
        }
        if updateVisibility {
            store.setVisionBoardVisibility(boardID, isVisible: true)
        }

        if let panel = panels[boardID] {
            panel.orderFrontRegardless()
            return
        }

        let index = store.visionBoards.firstIndex(where: { $0.id == boardID }) ?? 0
        let frameName = boardID == VisionBoard.primaryID
            ? "DigitalWallVisionBoardDesktopPanel"
            : "DigitalWallVisionBoardDesktopPanel-\(boardID.uuidString)"
        let panel = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 540, height: 340),
            minimumSize: NSSize(width: 260, height: 180),
            frameAutosaveName: frameName,
            defaultOffset: NSPoint(
                x: 36 + CGFloat(index % 5) * 38,
                y: 510 + CGFloat(index % 5) * 38
            ),
            acceptsFirstClick: true
        ) {
            VisionBoardDesktopPanelContent(
                store: store,
                boardID: boardID,
                openBoard: {
                    VisionBoardPresenter.shared.present(images: store.images(for: boardID))
                },
                hide: { [weak self] in
                    self?.dismiss(boardID: boardID, store: store)
                }
            )
        }

        panels[boardID] = panel
        panel.orderFrontRegardless()
    }

    func dismiss(boardID: UUID, store: WallStore) {
        if boardID == VisionBoard.primaryID {
            UserDefaults.standard.set(false, forKey: legacyEnabledKey)
        }
        store.setVisionBoardVisibility(boardID, isVisible: false)
        panels[boardID]?.orderOut(nil)
        panels[boardID] = nil
    }

    func remove(boardID: UUID, store: WallStore) {
        panels[boardID]?.orderOut(nil)
        panels[boardID] = nil
        store.removeVisionBoard(boardID)
    }

}

struct VisionBoardDesktopPanelContent: View {
    @ObservedObject var store: WallStore
    let boardID: UUID
    let openBoard: () -> Void
    let hide: () -> Void
    @State private var controlsVisible = false
    @State private var dropTargeted = false
    @State private var dropError: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DesktopPanelBackground()

            preview
                .contentShape(Rectangle())
                .onTapGesture {
                    if !allImages.isEmpty { openBoard() }
                }

            DesktopPanelControlMenu(isVisible: controlsVisible) {
                Button("Edit vision board", systemImage: "pencil") {
                    DashboardNavigation.shared.editBoard(boardID)
                }
                Divider()
                Button("Hide from desktop", systemImage: "eye.slash", action: hide)
            }
            .padding(12)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.blue.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.blue, lineWidth: 3)
                    }
                    .overlay {
                        Label("Add images to this board", systemImage: "photo.badge.plus")
                            .padding(12)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.url], isTargeted: $dropTargeted, perform: importDrop)
        .alert("Couldn’t add image", isPresented: Binding(
            get: { dropError != nil }, set: { if !$0 { dropError = nil } }
        )) {
            Button("OK") { dropError = nil }
        } message: {
            Text(dropError ?? "")
        }
        .onHover { controlsVisible = $0 }
    }

    func importDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        guard !supported.isEmpty else { return false }
        Task { @MainActor in
            store.lastError = nil
            // Import sequentially so multi-image drops retain their supplied order.
            for provider in supported {
                do {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let url = try await droppedURL(from: provider, type: .fileURL)
                        store.importImages(from: [url], to: boardID)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        // Providers own temporary file representations only during their callback.
                        let url: URL = try await withCheckedThrowingContinuation { continuation in
                            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                                do {
                                    if let error { throw error }
                                    guard let url else { throw CocoaError(.fileReadCorruptFile) }
                                    let copy = FileManager.default.temporaryDirectory
                                        .appendingPathComponent(UUID().uuidString)
                                        .appendingPathExtension(url.pathExtension.isEmpty ? "png" : url.pathExtension)
                                    try FileManager.default.copyItem(at: url, to: copy)
                                    continuation.resume(returning: copy)
                                } catch { continuation.resume(throwing: error) }
                            }
                        }
                        defer { try? FileManager.default.removeItem(at: url) }
                        store.importImages(from: [url], to: boardID)
                    } else {
                        let remoteURL = try await droppedURL(from: provider, type: .url)
                        let url = try await downloadDroppedImage(from: remoteURL)
                        defer { try? FileManager.default.removeItem(at: url) }
                        store.importImages(from: [url], to: boardID)
                    }
                    if let error = store.lastError { dropError = error }
                } catch {
                    store.lastError = error.localizedDescription
                    dropError = error.localizedDescription
                }
            }
        }
        return true
    }

    private func droppedURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = item as? URL { continuation.resume(returning: url) }
                else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else { continuation.resume(throwing: CocoaError(.fileReadCorruptFile)) }
            }
        }
    }

    private func downloadDroppedImage(from url: URL) async throws -> URL {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw ImageDropError.notAnImage
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (download, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: download) }
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let image = NSImage(contentsOf: download), image.isValid else {
            throw ImageDropError.notAnImage
        }
        // Use the decoded image type instead of trusting a URL suffix or server MIME type.
        guard let source = CGImageSourceCreateWithURL(download as CFURL, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String), type.conforms(to: .image),
              let ext = type.preferredFilenameExtension else { throw ImageDropError.notAnImage }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.moveItem(at: download, to: copy)
        return copy
    }

    private var board: VisionBoard? { store.visionBoard(boardID) }
    private var allImages: [VisionImage] { store.images(for: boardID) }
    private var previewImages: [VisionImage] { store.desktopPreviewImages(for: boardID) }

    private var preview: some View {
        Group {
            if store.visionBoardPrivacyEnabled {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.title2)
                    Text(store.visionBoardPrivacyMessage.isEmpty
                         ? "Private vision board"
                         : store.visionBoardPrivacyMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else if previewImages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                    Text(board?.name ?? "Vision board")
                        .font(.headline)
                    Text("Drop images here to add them")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                collage
            }
        }
        .padding(8)
    }

    private var collage: some View {
        GeometryReader { proxy in
            let images = previewImages
            let columns = optimalColumnCount(
                images: images,
                canvas: proxy.size,
                spacing: 4
            )
            let rows = max(1, Int(ceil(Double(images.count) / Double(columns))))
            let spacing: CGFloat = 4
            let width = max(1, (proxy.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
            let height = max(1, (proxy.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows))

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(width), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(images) { image in
                    LocalImageView(image: image)
                        .frame(width: width, height: height)
                        .background(.black.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func optimalColumnCount(
        images: [VisionImage],
        canvas: CGSize,
        spacing: CGFloat
    ) -> Int {
        let imageCount = images.count
        guard imageCount > 0 else { return 1 }
        func displayedImageArea(columns: Int) -> CGFloat {
            let rows = Int(ceil(Double(imageCount) / Double(columns)))
            let width = max(1, (canvas.width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
            let height = max(1, (canvas.height - CGFloat(rows - 1) * spacing) / CGFloat(rows))
            return images.reduce(0) { result, image in
                let imageSize = NSImage(contentsOf: WallPersistence.imageURL(for: image))?.size
                    ?? CGSize(width: 1, height: 1)
                let scale = min(width / max(1, imageSize.width), height / max(1, imageSize.height))
                return result + imageSize.width * scale * imageSize.height * scale
            }
        }
        return (1...imageCount).max { left, right in
            displayedImageArea(columns: left) < displayedImageArea(columns: right)
        } ?? 1
    }

}

private enum ImageDropError: LocalizedError {
    case notAnImage

    var errorDescription: String? {
        "This link didn’t return a readable image. Drag the image itself, or save it and drop the image file."
    }
}
