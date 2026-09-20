import AppKit
import SwiftUI

@MainActor
final class FullScreenOverlayController {
    private var panel: FullScreenOverlayPanel?
    private var keyMonitor: Any?
    private var dismissalTask: Task<Void, Never>?
    private var hideApplicationOnDismiss = false

    func present<Content: View>(
        hideApplicationOnDismiss: Bool,
        autoDismissAfter: Duration? = nil,
        dismissOnKeyDown: @escaping (NSEvent) -> Bool,
        @ViewBuilder content: (_ dismiss: @escaping () -> Void) -> Content
    ) {
        closePanel(hideApplication: false)

        let screen = screenUnderPointer() ?? NSScreen.main
        guard let screen else { return }

        let dismiss: () -> Void = { [weak self] in
            self?.dismiss()
        }
        let panel = FullScreenOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: content(dismiss))
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

private final class FullScreenOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
