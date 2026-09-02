import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        guard let boardID = store.visionBoards.first?.id else { return }
        present(boardID: boardID, store: store)
    }

    @discardableResult
    func createAndPresent(store: WallStore) -> UUID {
        let boardID = store.addVisionBoard()
        present(boardID: boardID, store: store)
        return boardID
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
                newBoard: { [weak self] in
                    _ = self?.createAndPresent(store: store)
                },
                beginEditing: { [weak self] in
                    self?.activateForEditing(boardID: boardID)
                },
                openBoard: {
                    VisionBoardPresenter.shared.present(images: store.images(for: boardID))
                },
                close: { [weak self] in
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

    private func activateForEditing(boardID: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        panels[boardID]?.makeKeyAndOrderFront(nil)
    }
}

private struct VisionBoardDesktopPanelContent: View {
    @ObservedObject var store: WallStore
    let boardID: UUID
    let newBoard: () -> Void
    let beginEditing: () -> Void
    let openBoard: () -> Void
    let close: () -> Void
    @State private var controlsVisible = false
    @State private var isEditing = false
    @State private var isImporting = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DesktopPanelBackground()

            if isEditing {
                editor
            } else {
                preview
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !allImages.isEmpty { openBoard() }
                    }
            }

            if !isEditing {
                DesktopPanelControlMenu(isVisible: controlsVisible) {
                    Button("Edit vision board", systemImage: "pencil") {
                        beginEditing()
                        isEditing = true
                    }

                    Button("New vision board", systemImage: "plus", action: newBoard)

                    Divider()

                    Button("Close", systemImage: "xmark", role: .destructive, action: close)
                }
                .padding(12)
            }
        }
        .onHover { controlsVisible = $0 }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                store.importImages(from: urls, to: boardID)
            case let .failure(error):
                store.lastError = error.localizedDescription
            }
        }
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
                    LocalImageView(image: image, contentMode: .fit)
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

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Add images…", systemImage: "plus") { isImporting = true }
                Spacer()
                Button("Done") { isEditing = false }
                    .buttonStyle(.borderedProminent)
            }

            TextField("Board name", text: boardNameBinding)
                .textFieldStyle(.roundedBorder)

            Toggle("Hide all photos in desktop previews", isOn: privacyBinding)
                .font(.callout.weight(.medium))

            if store.visionBoardPrivacyEnabled {
                TextField("Privacy message", text: privacyMessageBinding)
                    .textFieldStyle(.roundedBorder)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(allImages) { image in
                        HStack(spacing: 10) {
                            LocalImageView(image: image)
                                .frame(width: 54, height: 42)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(image.phrase.isEmpty ? "Image" : image.phrase)
                                .font(.caption)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            let hidden = board?.hiddenDesktopImageIDs.contains(image.id) == true
                            Button {
                                store.setImageHiddenOnDesktop(
                                    image.id,
                                    boardID: boardID,
                                    hidden: !hidden
                                )
                            } label: {
                                Image(systemName: hidden ? "eye.slash.fill" : "eye.fill")
                            }
                            .buttonStyle(.plain)
                            .help(hidden ? "Show in desktop preview" : "Hide only in desktop preview")

                            Button(role: .destructive) {
                                store.removeImage(image, from: boardID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("Remove from this board")
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .padding(14)
    }

    private var boardNameBinding: Binding<String> {
        Binding(
            get: { board?.name ?? "" },
            set: { store.updateVisionBoardName(boardID, name: $0) }
        )
    }

    private var privacyBinding: Binding<Bool> {
        Binding(
            get: { store.visionBoardPrivacyEnabled },
            set: { store.setVisionBoardPrivacy(enabled: $0) }
        )
    }

    private var privacyMessageBinding: Binding<String> {
        Binding(
            get: { store.visionBoardPrivacyMessage },
            set: { store.setVisionBoardPrivacyMessage($0) }
        )
    }
}
