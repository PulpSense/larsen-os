import SwiftUI
import AppKit

// Native UI fixture; submissions go only to the supplied test JSON file.
@main
@MainActor
struct HourCheckInOverlayHarness: App {
    @StateObject private var store: WallStore
    private let path: String
    @State private var previewReduceMotion = false

    init() {
        path = ProcessInfo.processInfo.arguments.dropFirst().first
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("digital-wall-review-state.json").path
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
                if let imageURL = Bundle.main.url(forResource: "drop-test", withExtension: "png") {
                    HStack {
                        Button("Test both drop providers") {
                            let target = VisionBoardDesktopPanelContent(
                                store: store, boardID: VisionBoard.primaryID, openBoard: {}, hide: {}
                            )
                            _ = target.importDrop([
                                NSItemProvider(item: imageURL as NSURL, typeIdentifier: "public.file-url"),
                                NSItemProvider(object: NSImage(contentsOf: imageURL)!)
                            ])
                        }
                        Text("Drag image file")
                            .padding(12)
                            .onDrag { NSItemProvider(contentsOf: imageURL)! }
                        Text("Drag image data")
                            .padding(12)
                            .onDrag { NSItemProvider(object: NSImage(contentsOf: imageURL)!) }
                        VisionBoardDesktopPanelContent(
                            store: store, boardID: VisionBoard.primaryID, openBoard: {}, hide: {}
                        )
                        .frame(width: 360, height: 180)
                    }
                }
                Button("Show test desktop board") {
                    VisionBoardDesktopPanelController.shared.present(store: store)
                }
                Toggle("Preview with reduced motion", isOn: $previewReduceMotion)
                ForEach(4...15, id: \.self) { hours in
                    Button("Preview \(hours) hours") {
                        DeepWorkCelebrationPresenter.shared.present(
                            hours: hours, streak: 3, hideApplicationOnDismiss: false,
                            reduceMotion: previewReduceMotion ? true : nil
                        )
                    }
                }
            }
            .padding(24)
            .onAppear {
                GlobalShortcut.checkIn.start {
                    try? "Triggered".write(toFile: path + ".status", atomically: true, encoding: .utf8)
                    HourCheckInPanelController.shared.toggle(store: store)
                }
                try? (GlobalShortcut.checkIn.errorMessage ?? "Registered").write(
                    toFile: path + ".status", atomically: true, encoding: .utf8
                )
            }
        }
    }
}
