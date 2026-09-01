import AppKit
import SwiftUI

struct LocalImageView: View {
    let image: VisionImage
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let nsImage = NSImage(contentsOf: WallPersistence.imageURL(for: image)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
