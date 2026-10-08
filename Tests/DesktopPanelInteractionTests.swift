import AppKit
import SwiftUI

@main
struct DesktopPanelInteractionTests {
    @MainActor
    static func main() {
        let panel = DesktopWallPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.setContentEditing(false)
        precondition(panel.isMovableByWindowBackground, "Display mode should allow dragging the panel")

        panel.setContentEditing(true)
        precondition(!panel.isMovableByWindowBackground, "Edit mode must reserve drag gestures for content")

        panel.setContentEditing(false)
        precondition(panel.isMovableByWindowBackground, "Leaving edit mode should restore panel dragging")

        let clickThroughPanel = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 200, height: 120),
            minimumSize: NSSize(width: 100, height: 80),
            frameAutosaveName: "DigitalWallClickThroughTest",
            acceptsFirstClick: true
        ) {
            Color.clear
        }
        precondition(
            clickThroughPanel.contentView?.acceptsFirstMouse(for: nil) == true,
            "An opted-in desktop widget must handle its first click while inactive"
        )
        clickThroughPanel.close()

        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        mainWindow.orderOut(nil)
        MainAppWindowPresenter.shared.register {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        MainAppWindowPresenter.shared.present()
        precondition(
            mainWindow.isVisible,
            "The shared widget menu action must restore the main app window"
        )
        mainWindow.close()

        let migrated = DesktopPanelSupport.migratedFrame(
            currentSize: NSSize(width: 680, height: 170),
            legacyFrame: NSRect(x: 40, y: 238, width: 707, height: 224),
            visibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1084)
        )
        precondition(migrated.origin == NSPoint(x: 40, y: 238), "A redesign should preserve the prior panel position")
        precondition(migrated.size == NSSize(width: 680, height: 170), "A redesign should keep its new compact size")

        let recovered = DesktopPanelSupport.migratedFrame(
            currentSize: NSSize(width: 680, height: 170),
            legacyFrame: NSRect(x: -900, y: -500, width: 707, height: 224),
            visibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1084)
        )
        precondition(recovered.minX >= 0 && recovered.minY >= 0, "An off-screen panel should be recovered into the visible frame")

        let visibleFrame = NSRect(x: 0, y: 0, width: 500, height: 500)
        let nearbyFrame = NSRect(x: 200, y: 0, width: 100, height: 100)
        let movementGuides = DesktopPanelSupport.movementGuides(
            NSRect(x: 94, y: 0, width: 100, height: 100),
            to: [nearbyFrame],
            within: visibleFrame
        )
        precondition(movementGuides.verticalGuide == 196, "Nearby spacing should offer a visual guide")
        precondition(movementGuides.horizontalGuide == 0, "Matching edges should offer a visual guide")

        let awayFromAlignment = DesktopPanelSupport.movementGuides(
            NSRect(x: 120, y: 120, width: 100, height: 100),
            to: [nearbyFrame],
            within: visibleFrame
        )
        precondition(
            awayFromAlignment.verticalGuide == nil && awayFromAlignment.horizontalGuide == nil,
            "Guides should disappear once the widget moves away from alignment"
        )

        let resizeGuides = DesktopPanelSupport.resizeGuides(
            NSRect(x: 0, y: 0, width: 196, height: 100),
            from: NSRect(x: 0, y: 0, width: 100, height: 100),
            to: [NSRect(x: 208, y: 0, width: 100, height: 100)],
            within: visibleFrame,
            minimumSize: NSSize(width: 80, height: 80)
        )
        precondition(resizeGuides.verticalGuide == 200, "Resizing should offer a nearby edge guide")

        // Exercise the actual notification coordinator, including its initial
        // registration and resize completion, so no delayed adjustment can
        // undo an intentionally overlapping position.
        let first = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 200, height: 120),
            minimumSize: NSSize(width: 100, height: 80),
            frameAutosaveName: "DigitalWallFreeMovementFirstTest"
        ) { Color.clear }
        let second = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 200, height: 120),
            minimumSize: NSSize(width: 100, height: 80),
            frameAutosaveName: "DigitalWallFreeMovementSecondTest",
            locksAspectRatio: true
        ) { Color.clear }
        first.orderFrontRegardless()
        second.orderFrontRegardless()
        let screen = NSScreen.main!.visibleFrame
        let start = NSRect(x: screen.midX - 100, y: screen.midY - 60, width: 200, height: 120)
        first.setFrame(start, display: false)
        let overlapping = start.offsetBy(dx: 20, dy: 10)
        second.setFrame(overlapping, display: false)
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: second)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(second.frame == overlapping, "Overlapping placement must survive registration and movement")
        let enlarged = NSRect(origin: overlapping.origin, size: NSSize(width: 300, height: 180))
        second.setFrame(enlarged, display: false)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: second)
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: second)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(second.frame == enlarged, "A proportional widget may resize over other widgets")
        precondition(first.frame == start, "Moving or resizing a widget must not displace its neighbor")
        first.close()
        second.close()

        print("PASS: desktop-widget free movement and alignment suggestions")
    }
}
