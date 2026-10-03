import SwiftUI
import AppKit

// Native UI fixture; submissions go only to the supplied test JSON file.
@main
@MainActor
struct HourCheckInOverlayHarness: App {
    @StateObject private var store: WallStore
    private let path: String

    init() {
        path = ProcessInfo.processInfo.arguments.dropFirst().first!
        let url = URL(fileURLWithPath: path)
        _store = StateObject(wrappedValue: WallStore(load: {
            guard let data = try? Data(contentsOf: url),
                  let state = try? JSONDecoder().decode(WallState.self, from: data) else { return .empty }
            return state
        }, save: { state in
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        }, readWebhookToken: { "" }, startWebhookSync: false))
    }

    var body: some Scene {
        Window("Isolated check-in test", id: "test") {
            VStack {
                Text("Test submissions are isolated from your real tracker.")
                Button("Open test form") {
                    HourCheckInPanelController.shared.present(store: store)

                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(24)
            .onAppear {
                CheckInShortcut.shared.start {
                    try? "Triggered".write(toFile: path + ".status", atomically: true, encoding: .utf8)
                    HourCheckInPanelController.shared.toggle(store: store)
                }
                try? (CheckInShortcut.shared.errorMessage ?? "Registered").write(
                    toFile: path + ".status", atomically: true, encoding: .utf8
                )
            }
        }
    }
}
