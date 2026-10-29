import AppKit
import Foundation
import UniformTypeIdentifiers

@main
struct VisionBoardDropTests {
    @MainActor
    static func main() async throws {
        let base = URL(string: ProcessInfo.processInfo.arguments[1])!
        var saved = WallState.empty
        let store = WallStore(load: { saved }, save: { saved = $0 }, startWebhookSync: false)
        let board = VisionBoard.primaryID
        let target = VisionBoardDesktopPanelContent(store: store, boardID: board, openBoard: {}, hide: {})
        defer {
            for image in store.images(for: board) {
                try? FileManager.default.removeItem(at: WallPersistence.imageURL(for: image))
            }
        }

        // A browser can offer only public.url, with no file URL or image representation.
        let imageURL = base.appendingPathComponent("image")
        let provider = NSItemProvider(object: imageURL as NSURL)
        precondition(provider.hasItemConformingToTypeIdentifier(UTType.url.identifier))
        precondition(!provider.hasItemConformingToTypeIdentifier(UTType.image.identifier))
        precondition(target.importDrop([provider]), "FAIL: browser image URL was rejected by the desktop drop handler")
        for _ in 0..<100 where store.images(for: board).isEmpty && store.lastError == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(store.images(for: board).count == 1, "FAIL: browser drop did not add an image: \(store.lastError ?? "timeout")")
        let image = store.images(for: board)[0]
        precondition(NSImage(contentsOf: WallPersistence.imageURL(for: image)) != nil)
        precondition(saved.visionBoards.first(where: { $0.id == board })?.imageIDs == [image.id])
        print("PASS: browser URL drop downloads and persists a viewable image even without a URL suffix or image MIME type")

        for path in ["not-an-image.png", "missing.png"] {
            store.lastError = nil
            let invalid = NSItemProvider(object: base.appendingPathComponent(path) as NSURL)
            precondition(target.importDrop([invalid]))
            for _ in 0..<100 where store.lastError == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
            precondition(store.lastError?.contains("readable image") == true)
            precondition(store.images(for: board).count == 1, "Failed downloads must not append a board image")
        }
        print("PASS: webpage and HTTP-error drops report an error without adding broken images")

        store.lastError = nil
        let localURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[2])
        precondition(target.importDrop([
            NSItemProvider(item: localURL as NSURL, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(object: NSImage(contentsOf: localURL)!)
        ]))
        for _ in 0..<100 where store.images(for: board).count < 3 && store.lastError == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(store.images(for: board).count == 3, "File URL and image-data drops must still work")
        print("PASS: file URL and raw image providers still import into the same board")
    }
}
