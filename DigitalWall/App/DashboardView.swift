import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: WallStore
    @State private var selection: Section = .vision

    enum Section: String, CaseIterable, Identifiable {
        case vision = "Vision board"
        case tracker = "Consistency"
        case phrases = "Phrases"
        case clocks = "World clocks"

        var id: Self { self }
        var icon: String {
            switch self {
            case .vision: "photo.on.rectangle.angled"
            case .tracker: "square.grid.3x3.fill"
            case .phrases: "quote.bubble.fill"
            case .clocks: "globe.americas.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
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
                switch selection {
                case .vision:
                    VisionBoardEditorView(store: store)
                case .tracker:
                    YearTrackerView(store: store)
                case .phrases:
                    PhrasesView(store: store)
                case .clocks:
                    WorldClocksView(store: store)
                }
            }
            .alert("Couldn’t save your wall", isPresented: errorBinding) {
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
