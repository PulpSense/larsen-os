import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VisionBoardEditorView: View {
    @ObservedObject var store: WallStore
    @ObservedObject private var navigation = DashboardNavigation.shared
    @State private var isImporting = false
    @State private var importingBoardID: UUID?
    @State private var savedExportURL: URL?
    @State private var savedExportCount = 1
    @State private var savedExportIsFolder = false
    @State private var isExportingImages = false
    @State private var croppingImage: VisionImage?
    @State private var cropFrameSize = CGSize(width: 4, height: 3)
    @State private var editingBoardNameID: UUID?
    @State private var draftBoardName = ""
    @FocusState private var isBoardNameFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            privacySettings

            HStack(spacing: 16) {
                boardList
                    .frame(width: 210)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            Label("Board details", systemImage: "square.stack")
                                .font(.headline)
                            Spacer()
                            Button("Open board", systemImage: "sparkles.rectangle.stack") {
                                VisionBoardPresenter.shared.present(images: selectedImages)
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedImages.isEmpty)
                        }

                        boardSettings

                        HStack(spacing: 8) {
                            Text("Images · \(selectedImages.count)")
                                .font(.headline)

                            Spacer()

                            Button(isExportingImages ? "Saving…" : "Save all", systemImage: "square.and.arrow.down.on.square") {
                                saveAllToDownloads()
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedImages.isEmpty || isExportingImages)
                            .help("Save every image in this board, including hidden images, to a new folder in Downloads.")

                            Button("Add", systemImage: "plus") {
                                chooseImages()
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedBoard == nil)
                            .help("Add images to this board")
                        }

                        if selectedImages.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                ForEach(selectedImages) { image in
                                    imageCard(image)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
            }

            exportStatus
        }
        .padding(28)
        .navigationTitle("Vision Boards")
        .onAppear {
            if navigation.selectedBoardID == nil {
                navigation.selectedBoardID = store.visionBoards.first?.id
            }
        }
        .onChange(of: navigation.selectedBoardID) { _, selectedID in
            if editingBoardNameID != nil, editingBoardNameID != selectedID {
                commitBoardNameEdit()
            }
        }
        .onChange(of: isBoardNameFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                commitBoardNameEdit()
            }
        }
        .task(id: savedExportURL) { @MainActor in
            guard let exportURL = savedExportURL else { return }
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard !Task.isCancelled, savedExportURL == exportURL else { return }
            savedExportURL = nil
        }
        .sheet(item: $croppingImage) { image in
            VisionImageCropEditor(image: image, frameSize: cropFrameSize) { focalPoint in
                store.updateImageFocalPoint(focalPoint, for: image.id)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            let destinationBoardID = importingBoardID
            importingBoardID = nil
            switch result {
            case let .success(urls):
                guard let destinationBoardID else { return }
                store.importImages(from: urls, to: destinationBoardID)
            case let .failure(error):
                store.lastError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Vision Boards")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Button("New board", systemImage: "plus.rectangle.on.rectangle") {
                    let boardID = store.addVisionBoard()
                    VisionBoardDesktopPanelController.shared.present(boardID: boardID, store: store)
                    navigation.selectedBoardID = boardID
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Each board has its own pictures and desktop window.")
                .foregroundStyle(.secondary)
        }
    }

    private var privacySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("All boards · Desktop privacy", systemImage: "eye.slash")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Toggle("Hide desktop previews", isOn: Binding(
                    get: { store.visionBoardPrivacyEnabled },
                    set: { store.setVisionBoardPrivacy(enabled: $0) }
                ))
                .toggleStyle(.switch)
                .fixedSize()
            }

            Text("Replaces pictures in every board’s desktop window with a private message. Opening a board still shows its pictures.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if store.visionBoardPrivacyEnabled {
                TextField("Private message", text: Binding(
                    get: { store.visionBoardPrivacyMessage },
                    set: { store.setVisionBoardPrivacyMessage($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    private var boardList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Boards", systemImage: "photo.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            List(selection: $navigation.selectedBoardID) {
                ForEach(store.visionBoards) { board in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(board.name.isEmpty ? "Untitled board" : board.name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text("\(board.imageIDs.count) images")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(board.isVisible ? "On desktop" : "Hidden")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Menu {
                            Button(board.isVisible ? "Hide from desktop" : "Show on desktop", systemImage: board.isVisible ? "eye.slash" : "eye") {
                                toggleVisibility(of: board)
                            }
                            if store.visionBoards.count > 1 {
                                Divider()
                                Button("Delete board", systemImage: "trash", role: .destructive) {
                                    delete(board)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 24, height: 24)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .help("Board actions")
                    }
                    .tag(board.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    private var boardSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let selectedBoard, editingBoardNameID == selectedBoard.id {
                    TextField("Board name", text: $draftBoardName)
                        .font(.title3.bold())
                        .textFieldStyle(.roundedBorder)
                        .focused($isBoardNameFocused)
                        .onSubmit { commitBoardNameEdit() }
                        .onExitCommand { cancelBoardNameEdit() }

                    Button("Save name", systemImage: "checkmark") {
                        commitBoardNameEdit()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                } else {
                    Text(selectedBoard.flatMap { $0.name.isEmpty ? nil : $0.name } ?? "Untitled board")
                        .font(.title3.bold())
                        .lineLimit(1)

                    Button("Rename board", systemImage: "pencil") {
                        beginBoardNameEdit()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(selectedBoard == nil)
                }
            }

            HStack {
                Text("Desktop window")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("Show on desktop", isOn: Binding(
                    get: { selectedBoard?.isVisible ?? false },
                    set: { visible in
                        guard let board = selectedBoard else { return }
                        setVisibility(visible, of: board)
                    }
                ))
                .toggleStyle(.switch)
                .fixedSize()
                .disabled(selectedBoard == nil)
            }
        }
    }

    private var exportStatus: some View {
        HStack(spacing: 8) {
            if let savedExportURL {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(savedExportIsFolder ? "\(savedExportCount) images saved to Downloads" : "Image saved to Downloads")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(savedExportIsFolder ? "Open folder" : "Show in Finder") {
                    if savedExportIsFolder {
                        NSWorkspace.shared.open(savedExportURL)
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([savedExportURL])
                    }
                }
                .buttonStyle(.borderless)

                Button {
                    self.savedExportURL = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss save status")
                .accessibilityLabel("Dismiss save status")
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add pictures to this board", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Select one image or many at once. Digital Wall copies them into private local storage.")
        } actions: {
            Button("Choose images…") { chooseImages() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 24))
    }

    private func imageCard(_ image: VisionImage) -> some View {
        let hidden = selectedBoard?.hiddenDesktopImageIDs.contains(image.id) == true
        return VStack(alignment: .leading, spacing: 10) {
            LocalImageView(image: image)
                .frame(height: 145)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ImageOrientationLabel(image: image)

            HStack(spacing: 8) {
                Picker("Image framing", selection: Binding(
                    get: { store.images.first(where: { $0.id == image.id })?.displayMode ?? .fit },
                    set: { store.updateImageDisplayMode($0, for: image.id) }
                )) {
                    Text("Fit").tag(VisionImageDisplayMode.fit)
                    Text("Fill").tag(VisionImageDisplayMode.fill)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Fit shows the entire image. Fill crops the edges to fill the frame.")

                if image.displayMode == .fill {
                    Button("Adjust crop", systemImage: "crop") {
                        let images = selectedImages
                        let index = images.firstIndex(where: { $0.id == image.id }) ?? 0
                        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
                        let canvas = screen?.frame.size ?? CGSize(width: 1920, height: 1080)
                        cropFrameSize = VisionBoardCardLayout(index: index, imageCount: images.count, canvas: canvas).imageSize
                        croppingImage = image
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            Text(image.displayMode == .fill ? "Fill frame · crops edges" : "Fit frame · shows entire image")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField(
                "Optional phrase",
                text: Binding(
                    get: { store.images.first(where: { $0.id == image.id })?.phrase ?? "" },
                    set: { store.updatePhrase($0, for: image.id) }
                )
            )
            .textFieldStyle(.plain)
            .font(.callout)

            HStack {
                Button {
                    guard let selectedBoardID = navigation.selectedBoardID else { return }
                    store.setImageHiddenOnDesktop(
                        image.id,
                        boardID: selectedBoardID,
                        hidden: !hidden
                    )
                } label: {
                    Label(
                        hidden ? "Hidden on desktop" : "Shown on desktop",
                        systemImage: hidden ? "eye.slash.fill" : "eye.fill"
                    )
                }
                .buttonStyle(.plain)
                .font(.caption)

                Spacer()

                Button {
                    saveToDownloads(image)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .help("Save to Downloads")
                .accessibilityLabel("Save image to Downloads")

                Button(role: .destructive) {
                    guard let selectedBoardID = navigation.selectedBoardID else { return }
                    store.removeImage(image, from: selectedBoardID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }

    private func saveToDownloads(_ image: VisionImage) {
        do {
            let downloads = try FileManager.default.url(
                for: .downloadsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            savedExportURL = try WallPersistence.exportImage(image, to: downloads)
            savedExportCount = 1
            savedExportIsFolder = false
        } catch {
            store.lastError = "Couldn’t save image to Downloads: \(error.localizedDescription)"
        }
    }

    private func chooseImages() {
        guard let selectedBoardID = navigation.selectedBoardID else { return }
        importingBoardID = selectedBoardID
        isImporting = true
    }

    private func saveAllToDownloads() {
        let images = selectedImages
        let boardName = selectedBoard?.name ?? "Vision board"
        guard !images.isEmpty, !isExportingImages else { return }
        isExportingImages = true

        Task { @MainActor in
            defer { isExportingImages = false }
            do {
                let downloads = try FileManager.default.url(
                    for: .downloadsDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let folder = try await Task.detached(priority: .userInitiated) {
                    try WallPersistence.exportImages(images, boardName: boardName, to: downloads)
                }.value
                savedExportURL = folder
                savedExportCount = images.count
                savedExportIsFolder = true
            } catch {
                store.lastError = "Couldn’t save all images to Downloads: \(error.localizedDescription)"
            }
        }
    }

    private var selectedBoard: VisionBoard? {
        guard let selectedBoardID = navigation.selectedBoardID else { return nil }
        return store.visionBoard(selectedBoardID)
    }

    private var selectedImages: [VisionImage] {
        guard let selectedBoardID = navigation.selectedBoardID else { return [] }
        return store.images(for: selectedBoardID)
    }

    private func beginBoardNameEdit() {
        guard let selectedBoard else { return }
        draftBoardName = selectedBoard.name
        editingBoardNameID = selectedBoard.id
        DispatchQueue.main.async { isBoardNameFocused = true }
    }

    private func commitBoardNameEdit() {
        guard let editingBoardNameID else { return }
        let name = draftBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.editingBoardNameID = nil
        isBoardNameFocused = false
        store.updateVisionBoardName(editingBoardNameID, name: name.isEmpty ? "Untitled board" : name)
    }

    private func cancelBoardNameEdit() {
        editingBoardNameID = nil
        isBoardNameFocused = false
    }

    private func toggleVisibility(of board: VisionBoard) {
        setVisibility(!board.isVisible, of: board)
    }

    private func setVisibility(_ visible: Bool, of board: VisionBoard) {
        if visible {
            VisionBoardDesktopPanelController.shared.present(boardID: board.id, store: store)
        } else {
            VisionBoardDesktopPanelController.shared.dismiss(boardID: board.id, store: store)
        }
    }

    private func delete(_ board: VisionBoard) {
        let remaining = store.visionBoards.filter { $0.id != board.id }
        VisionBoardDesktopPanelController.shared.remove(boardID: board.id, store: store)
        if navigation.selectedBoardID == board.id {
            navigation.selectedBoardID = remaining.first?.id
        }
    }
}
