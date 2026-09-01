import AppKit
import SwiftUI

enum DesktopPanelAnchor {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
}

@MainActor
enum DesktopPanelSupport {
    static func migratedFrame(
        currentSize: NSSize,
        legacyFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        let width = min(currentSize.width, visibleFrame.width)
        let height = min(currentSize.height, visibleFrame.height)
        let size = NSSize(width: width, height: height)
        let maxX = visibleFrame.maxX - width
        let maxY = visibleFrame.maxY - height
        let origin = NSPoint(
            x: min(max(legacyFrame.minX, visibleFrame.minX), maxX),
            y: min(max(legacyFrame.minY, visibleFrame.minY), maxY)
        )
        return NSRect(origin: origin, size: size)
    }

    static func makePanel<Content: View>(
        initialSize: NSSize,
        minimumSize: NSSize,
        frameAutosaveName: String,
        defaultAnchor: DesktopPanelAnchor = .topRight,
        defaultOffset: NSPoint = NSPoint(x: 36, y: 36),
        @ViewBuilder content: () -> Content
    ) -> DesktopWallPanel {
        let screen = screenUnderPointer() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin: NSPoint
        switch defaultAnchor {
        case .topRight:
            origin = NSPoint(
                x: visibleFrame.maxX - initialSize.width - defaultOffset.x,
                y: visibleFrame.maxY - initialSize.height - defaultOffset.y
            )
        case .topLeft:
            origin = NSPoint(
                x: visibleFrame.minX + defaultOffset.x,
                y: visibleFrame.maxY - initialSize.height - defaultOffset.y
            )
        case .bottomRight:
            origin = NSPoint(
                x: visibleFrame.maxX - initialSize.width - defaultOffset.x,
                y: visibleFrame.minY + defaultOffset.y
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visibleFrame.minX + defaultOffset.x,
                y: visibleFrame.minY + defaultOffset.y
            )
        }
        let panel = DesktopWallPanel(
            contentRect: NSRect(origin: origin, size: initialSize),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: content())
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        )
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.setContentEditing(false)
        panel.isExcludedFromWindowsMenu = true
        panel.minSize = minimumSize
        panel.setFrameAutosaveName(frameAutosaveName)
        return panel
    }

    private static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}

final class DesktopWallPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setContentEditing(_ isEditing: Bool) {
        isMovableByWindowBackground = !isEditing
    }
}

struct DesktopPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

struct DesktopPanelControlMenu<Items: View>: View {
    let isVisible: Bool
    private let items: Items

    init(isVisible: Bool, @ViewBuilder items: () -> Items) {
        self.isVisible = isVisible
        self.items = items()
    }

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(.easeOut(duration: 0.12), value: isVisible)
    }
}
