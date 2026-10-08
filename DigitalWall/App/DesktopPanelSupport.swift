import AppKit
import SwiftUI

enum DesktopPanelAnchor {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
}

struct DesktopWidgetAlignmentGuides {
    var verticalGuide: CGFloat?
    var horizontalGuide: CGFloat?
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
        acceptsFirstClick: Bool = false,
        locksAspectRatio: Bool = false,
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
        let rootView = content().ignoresSafeArea(edges: .top)
        if acceptsFirstClick {
            panel.contentView = FirstClickHostingView(rootView: rootView)
        } else {
            panel.contentView = NSHostingView(rootView: rootView)
        }
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
        if locksAspectRatio {
            let ratio = initialSize.width / initialSize.height
            let minimumWidth = max(minimumSize.width, minimumSize.height * ratio)
            panel.minSize = NSSize(width: minimumWidth, height: minimumWidth / ratio)
            panel.aspectRatio = initialSize
        } else {
            panel.minSize = minimumSize
        }
        panel.setFrameAutosaveName(frameAutosaveName)
        if locksAspectRatio {
            panel.setFrame(
                proportionalFrame(
                    panel.frame,
                    aspectRatio: initialSize.width / initialSize.height,
                    minimumSize: panel.minSize,
                    within: panel.screen?.visibleFrame ?? visibleFrame
                ),
                display: false
            )
        }
        DesktopWidgetAlignmentCoordinator.shared.register(panel)
        return panel
    }

    static func proportionalFrame(
        _ frame: NSRect,
        aspectRatio: CGFloat,
        minimumSize: NSSize,
        within visibleFrame: NSRect
    ) -> NSRect {
        let minimumWidth = max(minimumSize.width, minimumSize.height * aspectRatio)
        let availableWidth = min(visibleFrame.width, visibleFrame.height * aspectRatio)
        let width = min(max(frame.width, minimumWidth), availableWidth)
        let height = width / aspectRatio
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.maxY - height, visibleFrame.minY), visibleFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func movementGuides(
        _ proposedFrame: NSRect,
        to occupiedFrames: [NSRect],
        within visibleFrame: NSRect,
        spacing: CGFloat = 8,
        threshold: CGFloat = 5
    ) -> DesktopWidgetAlignmentGuides {
        var horizontalCandidates: [(origin: CGFloat, guide: CGFloat)] = [
            (visibleFrame.minX, visibleFrame.minX),
            (visibleFrame.maxX - proposedFrame.width, visibleFrame.maxX)
        ]
        var verticalCandidates: [(origin: CGFloat, guide: CGFloat)] = [
            (visibleFrame.minY, visibleFrame.minY),
            (visibleFrame.maxY - proposedFrame.height, visibleFrame.maxY)
        ]

        for occupied in occupiedFrames {
            horizontalCandidates.append(contentsOf: [
                (occupied.minX, occupied.minX),
                (occupied.maxX - proposedFrame.width, occupied.maxX),
                (occupied.midX - proposedFrame.width / 2, occupied.midX)
            ])
            verticalCandidates.append(contentsOf: [
                (occupied.minY, occupied.minY),
                (occupied.maxY - proposedFrame.height, occupied.maxY),
                (occupied.midY - proposedFrame.height / 2, occupied.midY)
            ])

            let verticallyRelated = proposedFrame.maxY >= occupied.minY - threshold
                && proposedFrame.minY <= occupied.maxY + threshold
            if verticallyRelated {
                horizontalCandidates.append(contentsOf: [
                    (
                        occupied.minX - spacing - proposedFrame.width,
                        occupied.minX - spacing / 2
                    ),
                    (occupied.maxX + spacing, occupied.maxX + spacing / 2)
                ])
            }

            let horizontallyRelated = proposedFrame.maxX >= occupied.minX - threshold
                && proposedFrame.minX <= occupied.maxX + threshold
            if horizontallyRelated {
                verticalCandidates.append(contentsOf: [
                    (
                        occupied.minY - spacing - proposedFrame.height,
                        occupied.minY - spacing / 2
                    ),
                    (occupied.maxY + spacing, occupied.maxY + spacing / 2)
                ])
            }
        }

        var verticalGuide: CGFloat?
        var horizontalGuide: CGFloat?

        if let guide = closestGuide(
            to: proposedFrame.minX,
            candidates: horizontalCandidates,
            threshold: threshold
        ) {
            verticalGuide = guide
        }

        if let guide = closestGuide(
            to: proposedFrame.minY,
            candidates: verticalCandidates,
            threshold: threshold
        ) {
            horizontalGuide = guide
        }

        return DesktopWidgetAlignmentGuides(
            verticalGuide: verticalGuide,
            horizontalGuide: horizontalGuide
        )
    }

    static func resizeGuides(
        _ proposedFrame: NSRect,
        from previousFrame: NSRect,
        to occupiedFrames: [NSRect],
        within visibleFrame: NSRect,
        minimumSize: NSSize,
        spacing: CGFloat = 8,
        threshold: CGFloat = 5
    ) -> DesktopWidgetAlignmentGuides {
        let activeEdges = resizedEdges(from: previousFrame, to: proposedFrame)
        let edgeTargets = [visibleFrame.minX, visibleFrame.maxX]
            + occupiedFrames.flatMap {
                [$0.minX, $0.maxX, $0.minX - spacing, $0.maxX + spacing]
            }
        let verticalTargets = [visibleFrame.minY, visibleFrame.maxY]
            + occupiedFrames.flatMap {
                [$0.minY, $0.maxY, $0.minY - spacing, $0.maxY + spacing]
            }
        var verticalGuide: CGFloat?
        var horizontalGuide: CGFloat?

        if activeEdges.left,
           let target = closestValue(to: proposedFrame.minX, values: edgeTargets, threshold: threshold),
           proposedFrame.maxX - target >= minimumSize.width {
            verticalGuide = target
        } else if activeEdges.right,
                  let target = closestValue(to: proposedFrame.maxX, values: edgeTargets, threshold: threshold),
                  target - proposedFrame.minX >= minimumSize.width {
            verticalGuide = target
        }

        if activeEdges.bottom,
           let target = closestValue(to: proposedFrame.minY, values: verticalTargets, threshold: threshold),
           proposedFrame.maxY - target >= minimumSize.height {
            horizontalGuide = target
        } else if activeEdges.top,
                  let target = closestValue(to: proposedFrame.maxY, values: verticalTargets, threshold: threshold),
                  target - proposedFrame.minY >= minimumSize.height {
            horizontalGuide = target
        }

        return DesktopWidgetAlignmentGuides(
            verticalGuide: verticalGuide,
            horizontalGuide: horizontalGuide
        )
    }

    private static func closestGuide(
        to value: CGFloat,
        candidates: [(origin: CGFloat, guide: CGFloat)],
        threshold: CGFloat
    ) -> CGFloat? {
        candidates
            .map { (value: $0.origin, guide: $0.guide, distance: abs(value - $0.origin)) }
            .filter { $0.distance <= threshold }
            .min { $0.distance < $1.distance }
            .map { $0.guide }
    }

    private static func closestValue(
        to value: CGFloat,
        values: [CGFloat],
        threshold: CGFloat
    ) -> CGFloat? {
        values
            .map { (value: $0, distance: abs(value - $0)) }
            .filter { $0.distance <= threshold }
            .min { $0.distance < $1.distance }?
            .value
    }

    private static func resizedEdges(
        from previousFrame: NSRect,
        to proposedFrame: NSRect
    ) -> (left: Bool, right: Bool, bottom: Bool, top: Bool) {
        let tolerance: CGFloat = 0.25
        return (
            abs(previousFrame.minX - proposedFrame.minX) > tolerance,
            abs(previousFrame.maxX - proposedFrame.maxX) > tolerance,
            abs(previousFrame.minY - proposedFrame.minY) > tolerance,
            abs(previousFrame.maxY - proposedFrame.maxY) > tolerance
        )
    }

    private static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}

@MainActor
private final class DesktopWidgetAlignmentCoordinator: NSObject {
    static let shared = DesktopWidgetAlignmentCoordinator()

    private var previousFrames: [ObjectIdentifier: NSRect] = [:]

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidFinishResizing(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func register(_ panel: DesktopWallPanel) {
        previousFrames[ObjectIdentifier(panel)] = panel.frame
    }

    @objc private func panelDidMove(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWallPanel,
              !panel.inLiveResize else { return }
        updateGuides(for: panel, resizing: false)
    }

    @objc private func panelDidResize(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWallPanel else { return }
        if panel.inLiveResize {
            updateGuides(for: panel, resizing: true)
        } else {
            previousFrames[ObjectIdentifier(panel)] = panel.frame
        }
    }

    @objc private func panelDidFinishResizing(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWallPanel else { return }
        previousFrames[ObjectIdentifier(panel)] = panel.frame
        DesktopAlignmentGuideController.shared.hide()
    }

    @objc private func panelWillClose(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWallPanel else { return }
        previousFrames.removeValue(forKey: ObjectIdentifier(panel))
        DesktopAlignmentGuideController.shared.hide()
    }

    private func updateGuides(for panel: DesktopWallPanel, resizing: Bool) {
        let identifier = ObjectIdentifier(panel)
        let previousFrame = previousFrames[identifier] ?? panel.frame
        previousFrames[identifier] = panel.frame
        guard panel.isVisible else { return }

        // Alignment is a visual suggestion. Never move or resize the panel here:
        // AppKit keeps the widget attached to the pointer, even across other widgets.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            DesktopAlignmentGuideController.shared.hide()
            return
        }
        let occupiedFrames = NSApp.windows.compactMap { window -> NSRect? in
            guard let other = window as? DesktopWallPanel,
                  other !== panel,
                  other.isVisible else { return nil }
            return other.frame
        }
        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
        let guides = resizing
            ? DesktopPanelSupport.resizeGuides(
                panel.frame,
                from: previousFrame,
                to: occupiedFrames,
                within: visibleFrame,
                minimumSize: panel.minSize
            )
            : DesktopPanelSupport.movementGuides(
                panel.frame,
                to: occupiedFrames,
                within: visibleFrame
            )
        showGuides(
            vertical: guides.verticalGuide,
            horizontal: guides.horizontalGuide,
            for: panel
        )
    }

    private func showGuides(
        vertical: CGFloat?,
        horizontal: CGFloat?,
        for panel: DesktopWallPanel
    ) {
        guard vertical != nil || horizontal != nil,
              let screen = panel.screen ?? NSScreen.main else {
            DesktopAlignmentGuideController.shared.hide()
            return
        }
        DesktopAlignmentGuideController.shared.show(
            vertical: vertical,
            horizontal: horizontal,
            on: screen
        )
    }
}

@MainActor
private final class DesktopAlignmentGuideController {
    static let shared = DesktopAlignmentGuideController()

    private var panel: NSPanel?
    private var guideView: DesktopAlignmentGuideView?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func show(vertical: CGFloat?, horizontal: CGFloat?, on screen: NSScreen) {
        let panel = guidePanel(for: screen)
        guideView?.verticalGuide = vertical
        guideView?.horizontalGuide = horizontal
        guideView?.screenFrame = screen.visibleFrame
        guideView?.needsDisplay = true
        panel.orderFrontRegardless()
        scheduleHide()
    }

    func scheduleHide() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func guidePanel(for screen: NSScreen) -> NSPanel {
        if let panel, panel.frame == screen.visibleFrame { return panel }

        panel?.orderOut(nil)
        let guideView = DesktopAlignmentGuideView(frame: NSRect(origin: .zero, size: screen.visibleFrame.size))
        let panel = NSPanel(
            contentRect: screen.visibleFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = guideView
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        self.panel = panel
        self.guideView = guideView
        return panel
    }
}

private final class DesktopAlignmentGuideView: NSView {
    var verticalGuide: CGFloat?
    var horizontalGuide: CGFloat?
    var screenFrame = NSRect.zero

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard verticalGuide != nil || horizontalGuide != nil else { return }

        NSColor.lightGray.withAlphaComponent(0.4).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)

        if let verticalGuide {
            let x = verticalGuide - screenFrame.minX
            path.move(to: NSPoint(x: x, y: bounds.minY))
            path.line(to: NSPoint(x: x, y: bounds.maxY))
        }

        if let horizontalGuide {
            let y = horizontalGuide - screenFrame.minY
            path.move(to: NSPoint(x: bounds.minX, y: y))
            path.line(to: NSPoint(x: bounds.maxX, y: y))
        }

        path.stroke()
    }
}

final class DesktopWallPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setContentEditing(_ isEditing: Bool) {
        isMovableByWindowBackground = !isEditing
    }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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
            .ignoresSafeArea()
    }
}

@MainActor
final class MainAppWindowPresenter {
    static let shared = MainAppWindowPresenter()

    private var openMainWindow: (() -> Void)?

    private init() {}

    func register(openWindow: @escaping () -> Void) {
        openMainWindow = openWindow
    }

    func present() {
        NSApp.setActivationPolicy(.regular)

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
            DispatchQueue.main.async { [weak self] in
                self?.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }
    }
}

struct DesktopWidgetVisibilityToggle: View {
    @ObservedObject private var visibility = DesktopWidgetVisibility.shared
    let widget: DesktopWidgetVisibility.Widget
    let setVisibility: (Bool) -> Void

    var body: some View {
        Toggle("Show on desktop", isOn: Binding(
            get: { visibility.isVisible(widget) },
            set: setVisibility
        ))
        .toggleStyle(.switch)
        .fixedSize()
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
            Button("Open Digital Wall", systemImage: "macwindow") {
                MainAppWindowPresenter.shared.present()
            }

            Divider()

            items
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
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
