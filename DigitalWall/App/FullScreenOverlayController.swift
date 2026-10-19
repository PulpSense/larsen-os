import AppKit
import SwiftUI

@MainActor
final class FullScreenOverlayController {
    private var panel: FullScreenOverlayPanel?
    private var backdrops: [NSPanel] = []
    private var keyMonitor: Any?
    private var dismissalTask: Task<Void, Never>?
    private var hideApplicationOnDismiss = false
    private var onDismiss: (() -> Void)?
    private var presentationID = UUID()

    func present<Content: View>(
        hideApplicationOnDismiss: Bool,
        autoDismissAfter: Duration? = nil,
        nonactivating: Bool = false,
        preferredSize: NSSize? = nil,
        dimBackground: Bool = false,
        onDismiss: (() -> Void)? = nil,
        dismissOnKeyDown: @escaping (NSEvent) -> Bool,
        @ViewBuilder content: (_ dismiss: @escaping () -> Void) -> Content
    ) {
        closePanel(hideApplication: false)
        let presentationID = UUID()
        self.presentationID = presentationID

        let screen = screenUnderPointer() ?? NSScreen.main
        guard let screen else {
            onDismiss?()
            return
        }

        let dismiss: () -> Void = { [weak self] in
            guard let self, self.presentationID == presentationID else { return }
            self.dismiss()
        }
        let frame: NSRect
        if let preferredSize {
            let visibleFrame = screen.visibleFrame
            let size = NSSize(
                width: min(preferredSize.width, visibleFrame.width * 0.8),
                height: min(preferredSize.height, visibleFrame.height * 0.8)
            )
            frame = NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width, height: size.height
            )
        } else {
            frame = screen.frame
        }
        let panel = FullScreenOverlayPanel(
            contentRect: frame,
            styleMask: nonactivating ? [.borderless, .nonactivatingPanel] : [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: content(dismiss))
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = preferredSize != nil
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.setFrame(frame, display: true)
        panel.isReleasedWhenClosed = false
        self.panel = panel
        self.hideApplicationOnDismiss = hideApplicationOnDismiss
        self.onDismiss = onDismiss
        if dimBackground {
            for display in NSScreen.screens {
                let backdrop = OverlayBackdropPanel(
                    contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false
                )
                backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
                backdrop.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.72)
                backdrop.isOpaque = false
                backdrop.hasShadow = false
                backdrop.hidesOnDeactivate = false
                backdrop.isReleasedWhenClosed = false
                backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
                backdrop.dismissAction = dismiss
                backdrop.orderFrontRegardless()
                backdrops.append(backdrop)
            }
        }
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard dismissOnKeyDown(event) else { return event }
            self?.dismiss()
            return nil
        }

        if let autoDismissAfter {
            dismissalTask = Task { [weak self] in
                try? await Task.sleep(for: autoDismissAfter)
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        closePanel(hideApplication: hideApplicationOnDismiss)
    }

    private func closePanel(hideApplication: Bool) {
        dismissalTask?.cancel()
        dismissalTask = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.close()
        panel?.contentView = nil
        panel = nil
        backdrops.forEach { $0.close() }
        backdrops.removeAll()
        hideApplicationOnDismiss = false
        let completion = onDismiss
        onDismiss = nil
        if let completion { DispatchQueue.main.async { completion() } }

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

private final class FullScreenOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class OverlayBackdropPanel: NSPanel {
    var dismissAction: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func mouseDown(with event: NSEvent) { dismissAction?() }
}
