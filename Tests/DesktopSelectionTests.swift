import SwiftUI

@MainActor
final class WallStore: ObservableObject {
    @Published var visionBoards: [VisionBoard] = []
    @Published var desktopPhrases: [DesktopPhrase] = []
    @Published var lastError: String?

    func visionBoard(_ id: UUID) -> VisionBoard? { visionBoards.first { $0.id == id } }
    func desktopPhrase(_ id: UUID) -> DesktopPhrase? { desktopPhrases.first { $0.id == id } }
}

struct StubEditorView: View {
    let store: WallStore
    var body: some View { EmptyView() }
}

typealias VisionBoardEditorView = StubEditorView
typealias YearTrackerView = StubEditorView
typealias PhrasesView = StubEditorView
typealias WorldClocksView = StubEditorView

struct YearProgressView: View {
    var body: some View { EmptyView() }
}

@MainActor
final class MainAppWindowPresenter {
    static let shared = MainAppWindowPresenter()
    func present() {}
}

@main
enum DesktopSelectionTests {
    @MainActor
    static func main() {
        let store = WallStore()
        let firstBoard = VisionBoard(name: "First")
        let secondBoard = VisionBoard(name: "Second")
        let firstPhrase = DesktopPhrase(markdown: "First")
        let secondPhrase = DesktopPhrase(markdown: "Second")
        store.visionBoards = [firstBoard, secondBoard]
        store.desktopPhrases = [firstPhrase, secondPhrase]

        let navigation = DashboardNavigation.shared
        precondition(navigation.boardID(in: store) == firstBoard.id)
        precondition(navigation.phraseID(in: store) == firstPhrase.id)

        navigation.selectedBoardID = secondBoard.id
        navigation.selectedPhraseID = secondPhrase.id
        precondition(navigation.boardID(in: store) == secondBoard.id)
        precondition(navigation.phraseID(in: store) == secondPhrase.id)

        navigation.selectedBoardID = UUID()
        navigation.selectedPhraseID = UUID()
        precondition(navigation.boardID(in: store) == firstBoard.id)
        precondition(navigation.phraseID(in: store) == firstPhrase.id)

        store.visionBoards = []
        store.desktopPhrases = []
        precondition(navigation.boardID(in: store) == nil)
        precondition(navigation.phraseID(in: store) == nil)
        print("PASS: global Show actions use valid selections and fall back safely")
    }
}
