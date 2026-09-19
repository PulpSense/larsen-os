import SwiftUI
import UniformTypeIdentifiers

struct VisionBoardEditorView: View {
    @ObservedObject var store: WallStore
    @State private var selectedBoardID: UUID?
    @State private var isImporting = false

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            HSplitView {
                boardList
                    .frame(minWidth: 185, idealWidth: 210, maxWidth: 250)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        boardSettings

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
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(28)
        .navigationTitle("Vision Boards")
        .onAppear {
            if selectedBoardID == nil {
                selectedBoardID = store.visionBoards.first?.id
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                guard let selectedBoardID else { return }
                store.importImages(from: urls, to: selectedBoardID)
            case let .failure(error):
                store.lastError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Vision Boards")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Each board has its own pictures, privacy choices, and desktop window.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("New board", systemImage: "plus.rectangle.on.rectangle") {
                let boardID = VisionBoardDesktopPanelController.shared.createAndPresent(store: store)
                selectedBoardID = boardID
            }
            .buttonStyle(.borderedProminent)

            Button("Add images…", systemImage: "plus") {
                isImporting = true
            }
            .buttonStyle(.bordered)
            .disabled(selectedBoardID == nil)

            Button("Show on Desktop", systemImage: "rectangle.on.rectangle") {
                guard let selectedBoardID else { return }
                VisionBoardDesktopPanelController.shared.present(
                    boardID: selectedBoardID,
                    store: store
                )
            }
            .buttonStyle(.bordered)

            Button("Show", systemImage: "sparkles.rectangle.stack") {
                VisionBoardPresenter.shared.present(images: selectedImages)
            }
            .buttonStyle(.bordered)
            .disabled(selectedImages.isEmpty)
        }
    }

    private var boardList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Boards", systemImage: "photo.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            List(selection: $selectedBoardID) {
                ForEach(store.visionBoards) { board in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(board.name.isEmpty ? "Untitled board" : board.name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text("\(board.imageIDs.count) images")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            toggleVisibility(of: board)
                        } label: {
                            Image(systemName: board.isVisible ? "eye.fill" : "eye.slash")
                        }
                        .buttonStyle(.plain)

                        if store.visionBoards.count > 1 {
                            Button(role: .destructive) { delete(board) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .tag(board.id)
                }
            }
            .listStyle(.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var boardSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Board name", text: boardNameBinding)
                .font(.title3.bold())
                .textFieldStyle(.roundedBorder)

            GroupBox("Desktop privacy") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Replace every board’s desktop pictures with a private message", isOn: privacyBinding)
                    if store.visionBoardPrivacyEnabled {
                        TextField("Privacy message", text: privacyMessageBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Pictures hidden individually below still appear when you open the full board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add pictures to this board", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Select one image or many at once. Digital Wall copies them into private local storage.")
        } actions: {
            Button("Choose images…") { isImporting = true }
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
                    guard let selectedBoardID else { return }
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

                Button(role: .destructive) {
                    guard let selectedBoardID else { return }
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

    private var selectedBoard: VisionBoard? {
        guard let selectedBoardID else { return nil }
        return store.visionBoard(selectedBoardID)
    }

    private var selectedImages: [VisionImage] {
        guard let selectedBoardID else { return [] }
        return store.images(for: selectedBoardID)
    }

    private var boardNameBinding: Binding<String> {
        Binding(
            get: { selectedBoard?.name ?? "" },
            set: { name in
                guard let selectedBoardID else { return }
                store.updateVisionBoardName(selectedBoardID, name: name)
            }
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

    private func toggleVisibility(of board: VisionBoard) {
        if board.isVisible {
            VisionBoardDesktopPanelController.shared.dismiss(boardID: board.id, store: store)
        } else {
            VisionBoardDesktopPanelController.shared.present(boardID: board.id, store: store)
        }
    }

    private func delete(_ board: VisionBoard) {
        let remaining = store.visionBoards.filter { $0.id != board.id }
        VisionBoardDesktopPanelController.shared.remove(boardID: board.id, store: store)
        if selectedBoardID == board.id {
            selectedBoardID = remaining.first?.id
        }
    }
}
