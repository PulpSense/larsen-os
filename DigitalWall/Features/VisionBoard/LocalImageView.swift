import AppKit
import SwiftUI

struct LocalImageView: View {
    let image: VisionImage

    var body: some View {
        Group {
            if let nsImage = NSImage(contentsOf: WallPersistence.imageURL(for: image)) {
                VisionImageContentView(nsImage: nsImage, displayMode: image.displayMode, focalPoint: image.focalPoint)
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

struct ImageOrientationLabel: View {
    let image: VisionImage

    var body: some View {
        if let size = NSImage(contentsOf: WallPersistence.imageURL(for: image))?.size,
           size.width > 0, size.height > 0 {
            Group {
                if size.height > size.width {
                    Label("Vertical", systemImage: "rectangle.portrait")
                } else if size.width > size.height {
                    Label("Horizontal", systemImage: "rectangle")
                } else {
                    Label("Square", systemImage: "square")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }
}

struct VisionImageContentView: View {
    let nsImage: NSImage
    let displayMode: VisionImageDisplayMode
    let focalPoint: VisionImageFocalPoint

    var body: some View {
        if displayMode == .fill {
            GeometryReader { proxy in
                let crop = VisionImageCropGeometry(imageSize: nsImage.size, frameSize: proxy.size, focalPoint: focalPoint)
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: crop.renderedSize.width, height: crop.renderedSize.height)
                    .position(
                        x: crop.origin.x + crop.renderedSize.width / 2,
                        y: crop.origin.y + crop.renderedSize.height / 2
                    )
            }
            .clipped()
        } else {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        }
    }
}
