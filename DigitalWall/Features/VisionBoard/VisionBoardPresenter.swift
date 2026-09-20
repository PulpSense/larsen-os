import AppKit
import SwiftUI

@MainActor
final class VisionBoardPresenter {
    static let shared = VisionBoardPresenter()

    private var panel: VisionBoardPanel?
    private var keyMonitor: Any?
    private var hideApplicationOnDismiss = false

    private init() {}

    func present(images: [VisionImage], hideApplicationOnDismiss: Bool = false) {
        present(
            items: images.map {
                PresentedVisionImage(
                    id: $0.id.uuidString,
                    url: WallPersistence.imageURL(for: $0),
                    phrase: $0.phrase
                )
            },
            hideApplicationOnDismiss: hideApplicationOnDismiss
        )
    }

    func present(imageURLs: [URL], hideApplicationOnDismiss: Bool = false) {
        present(
            items: imageURLs.map { PresentedVisionImage(id: $0.path, url: $0, phrase: "") },
            hideApplicationOnDismiss: hideApplicationOnDismiss
        )
    }

    private func present(items: [PresentedVisionImage], hideApplicationOnDismiss: Bool) {
        guard !items.isEmpty else { return }
        closePanel(hideApplication: false)

        let screen = screenUnderPointer() ?? NSScreen.main
        guard let screen else { return }

        let content = ImmersiveVisionBoard(images: items) { [weak self] in
            self?.dismiss()
        }
        let panel = VisionBoardPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: content)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.setFrame(screen.frame, display: true)
        self.panel = panel
        self.hideApplicationOnDismiss = hideApplicationOnDismiss
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.dismiss()
            return nil
        }
    }

    func dismiss() {
        closePanel(hideApplication: hideApplicationOnDismiss)
    }

    private func closePanel(hideApplication: Bool) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        hideApplicationOnDismiss = false

        if hideApplication {
            DispatchQueue.main.async {
                NSApp.hide(nil)
            }
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}

private struct PresentedVisionImage: Identifiable {
    let id: String
    let url: URL
    let phrase: String
}

private final class VisionBoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct ImmersiveVisionBoard: View {
    let images: [PresentedVisionImage]
    let dismiss: () -> Void
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.black.opacity(appeared ? 0.48 : 0))
                    .background(.ultraThinMaterial)

                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    visionCard(image, index: index, canvas: proxy.size)
                }

                VStack {
                    Spacer()
                    Text("Press any key or click anywhere to return")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.32), in: Capsule())
                        .padding(.bottom, 28)
                }
                .opacity(appeared ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
            .onAppear {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
                    appeared = true
                }
            }
        }
        .ignoresSafeArea()
    }

    private func visionCard(_ image: PresentedVisionImage, index: Int, canvas: CGSize) -> some View {
        let featuredLayouts: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.22, 0.27, -4, 0.25), (0.50, 0.22, 3, 0.23),
            (0.78, 0.28, -2, 0.25), (0.31, 0.62, 2, 0.24),
            (0.66, 0.61, -3, 0.26), (0.10, 0.70, 4, 0.19),
            (0.88, 0.68, -4, 0.18), (0.50, 0.47, 1, 0.20)
        ]
        let layout: (CGFloat, CGFloat, CGFloat, CGFloat)
        let maximumCardHeight: CGFloat
        if images.count <= featuredLayouts.count {
            layout = featuredLayouts[index]
            maximumCardHeight = canvas.height * 0.32
        } else {
            let columns = Int(ceil(sqrt(Double(images.count))))
            let rows = Int(ceil(Double(images.count) / Double(columns)))
            let row = index / columns
            let column = index % columns
            let imagesInRow = min(columns, images.count - row * columns)
            let horizontalOffset = CGFloat(columns - imagesInRow) / 2
            let x = (CGFloat(column) + horizontalOffset + 0.5) / CGFloat(columns)
            let y = (CGFloat(row) + 0.5) / CGFloat(rows)
            let rotation = CGFloat((index % 3) - 1) * 1.5
            layout = (
                0.08 + x * 0.84,
                0.08 + y * 0.76,
                rotation,
                min(0.22, 0.78 / CGFloat(columns))
            )
            maximumCardHeight = canvas.height * min(0.24, 0.68 / CGFloat(rows))
        }
        let width = min(max(canvas.width * layout.3, 190), 420)

        return VStack(spacing: 10) {
            Group {
                if let nsImage = NSImage(contentsOf: image.url) {
                    Image(nsImage: nsImage).resizable().scaledToFit()
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
                .frame(maxWidth: width, maxHeight: maximumCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !image.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(image.phrase)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .padding(10)
        .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .rotationEffect(.degrees(layout.2))
        .position(x: canvas.width * layout.0, y: canvas.height * layout.1)
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .animation(
            .spring(response: 0.58, dampingFraction: 0.78)
                .delay(Double(index) * 0.055),
            value: appeared
        )
    }
}
