import AppKit
import SwiftUI

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

private struct VisionBoardDesktopPanelContent: View {
    @ObservedObject var store: WallStore
    let boardID: UUID
    let openBoard: () -> Void
    let hide: () -> Void
    @State private var controlsVisible = false

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
        .onHover { controlsVisible = $0 }
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
