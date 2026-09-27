import AppKit
import SwiftUI

struct VisionImageCropEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var focalPoint: VisionImageFocalPoint
    @GestureState private var dragTranslation: CGSize = .zero

    private let nsImage: NSImage?
    private let frameSize: CGSize
    private let save: (VisionImageFocalPoint) -> Void

    init(image: VisionImage, frameSize: CGSize, save: @escaping (VisionImageFocalPoint) -> Void) {
        nsImage = NSImage(contentsOf: WallPersistence.imageURL(for: image))
        self.frameSize = frameSize
        self.save = save
        _focalPoint = State(initialValue: image.focalPoint)
    }

    private var previewSize: CGSize {
        let scale = min(560 / max(1, frameSize.width), 300 / max(1, frameSize.height))
        return CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjust crop")
                .font(.title2.bold())
            Text("Drag the image to choose what stays visible in the opened board. Desktop previews use the same focus.")
                .foregroundStyle(.secondary)

            if let nsImage {
                let geometry = VisionImageCropGeometry(imageSize: nsImage.size, frameSize: previewSize, focalPoint: focalPoint)

                VisionImageContentView(
                    nsImage: nsImage,
                    displayMode: .fill,
                    focalPoint: geometry.focalPoint(afterDragging: dragTranslation)
                )
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.primary.opacity(0.2), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .updating($dragTranslation) { value, translation, _ in
                            translation = value.translation
                        }
                        .onEnded { value in
                            focalPoint = geometry.focalPoint(afterDragging: value.translation)
                        }
                )
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Crop preview")
                .accessibilityHint("Use the position sliders to adjust the crop.")

                if geometry.horizontalRange.upperBound - geometry.horizontalRange.lowerBound > 0.001 {
                    Slider(value: Binding(
                        get: { min(max(focalPoint.x, geometry.horizontalRange.lowerBound), geometry.horizontalRange.upperBound) },
                        set: { focalPoint = VisionImageFocalPoint(x: $0, y: focalPoint.y) }
                    ), in: geometry.horizontalRange) {
                        Text("Horizontal position")
                    }
                }
                if geometry.verticalRange.upperBound - geometry.verticalRange.lowerBound > 0.001 {
                    Slider(value: Binding(
                        get: { min(max(focalPoint.y, geometry.verticalRange.lowerBound), geometry.verticalRange.upperBound) },
                        set: { focalPoint = VisionImageFocalPoint(x: focalPoint.x, y: $0) }
                    ), in: geometry.verticalRange) {
                        Text("Vertical position")
                    }
                }
                if geometry.horizontalRange.upperBound - geometry.horizontalRange.lowerBound <= 0.001,
                   geometry.verticalRange.upperBound - geometry.verticalRange.lowerBound <= 0.001 {
                    Text("The entire image already fits this frame.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo")
                    .frame(height: 220)
            }

            HStack {
                Button("Reset to center") { focalPoint = .center }
                    .disabled(nsImage == nil)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save crop") {
                    save(focalPoint)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(nsImage == nil)
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}
