import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: WallStore
    @ObservedObject private var navigation = DashboardNavigation.shared

    enum Section: String, CaseIterable, Identifiable {
        case vision = "Vision Boards"
        case tracker = "Deep Work Hours"
        case yearProgress = "Year Elapsed"
        case phrases = "Phrases"
        case clocks = "World Clocks"

        var id: Self { self }
        var icon: String {
            switch self {
            case .vision: "photo.on.rectangle.angled"
            case .tracker: "square.grid.3x3.fill"
            case .yearProgress: "chart.bar.fill"
            case .phrases: "quote.bubble.fill"
            case .clocks: "globe.americas.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $navigation.section) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("Stored locally")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
            }
        } detail: {
            Group {
                switch navigation.section {
                case .vision:
                    VisionBoardEditorView(store: store)
                case .tracker:
                    YearTrackerView(store: store)
                case .yearProgress:
                    YearProgressView()
                case .phrases:
                    PhrasesView(store: store)
                case .clocks:
                    WorldClocksView(store: store)
                }
            }
            .alert("Couldn’t complete action", isPresented: errorBinding) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "Unknown error")
            }
        }
        .tint(.indigo)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}

@MainActor
final class DashboardNavigation: ObservableObject {
    static let shared = DashboardNavigation()

    @Published var section: DashboardView.Section = .vision
    @Published var selectedBoardID: UUID?
    @Published var selectedPhraseID: UUID?
    @Published var editingPhraseID: UUID?

    private init() {}

    func boardID(in store: WallStore) -> UUID? {
        if let selectedBoardID, store.visionBoard(selectedBoardID) != nil {
            return selectedBoardID
        }
        return store.visionBoards.first?.id
    }

    func phraseID(in store: WallStore) -> UUID? {
        if let selectedPhraseID, store.desktopPhrase(selectedPhraseID) != nil {
            return selectedPhraseID
        }
        return store.desktopPhrases.first?.id
    }

    func editBoard(_ id: UUID) {
        selectedBoardID = id
        section = .vision
        MainAppWindowPresenter.shared.present()
    }

    func editPhrase(_ id: UUID) {
        selectedPhraseID = id
        editingPhraseID = id
        section = .phrases
        MainAppWindowPresenter.shared.present()
    }

    func open(_ section: DashboardView.Section) {
        self.section = section
        MainAppWindowPresenter.shared.present()
    }
}
