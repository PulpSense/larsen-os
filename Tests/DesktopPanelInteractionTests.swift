import AppKit

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

        let occupiedFrame = NSRect(x: 90, y: 0, width: 100, height: 100)
        let spaced = DesktopPanelSupport.spacedFrame(
            NSRect(x: 80, y: 0, width: 100, height: 100),
            avoiding: [occupiedFrame],
            within: NSRect(x: 0, y: 0, width: 500, height: 500)
        )
        let occupiedExclusion = occupiedFrame.insetBy(
            dx: -DesktopPanelSupport.minimumWidgetSpacing,
            dy: -DesktopPanelSupport.minimumWidgetSpacing
        )
        precondition(
            !spaced.intersects(occupiedExclusion),
            "Overlapping widgets should settle with the minimum gap"
        )

        let alreadySpaced = DesktopPanelSupport.spacedFrame(
            spaced,
            avoiding: [occupiedFrame],
            within: NSRect(x: 0, y: 0, width: 500, height: 500)
        )
        precondition(alreadySpaced == spaced, "A correctly spaced widget should not move")

        let liveBarrier = DesktopPanelSupport.constrainedFrame(
            NSRect(x: 150, y: 0, width: 100, height: 100),
            from: NSRect(x: 0, y: 0, width: 100, height: 100),
            avoiding: [NSRect(x: 104, y: 0, width: 100, height: 100)],
            within: NSRect(x: 0, y: 0, width: 500, height: 500)
        )
        precondition(
            liveBarrier.maxX == 100,
            "A dragged widget should stop at the gap instead of passing through"
        )

        let aroundTheEdge = DesktopPanelSupport.constrainedFrame(
            NSRect(x: 150, y: 120, width: 100, height: 100),
            from: NSRect(x: 0, y: 0, width: 100, height: 100),
            avoiding: [NSRect(x: 104, y: 0, width: 100, height: 100)],
            within: NSRect(x: 0, y: 0, width: 500, height: 500)
        )
        precondition(
            aroundTheEdge.origin == NSPoint(x: 150, y: 120),
            "A widget should still be able to move around another widget's edge"
        )

        let moveSnap = DesktopPanelSupport.snappedFrame(
            NSRect(x: 94, y: 0, width: 100, height: 100),
            to: [NSRect(x: 200, y: 0, width: 100, height: 100)],
            within: NSRect(x: 0, y: 0, width: 500, height: 500)
        )
        precondition(
            moveSnap.frame.minX == 96,
            "Positioning near another widget should snap to the shared gap"
        )
        precondition(moveSnap.verticalGuide != nil, "A position snap should provide a guide")

        let resizeSnap = DesktopPanelSupport.snappedResizeFrame(
            NSRect(x: 0, y: 0, width: 196, height: 100),
            from: NSRect(x: 0, y: 0, width: 100, height: 100),
            to: [NSRect(x: 204, y: 0, width: 100, height: 100)],
            within: NSRect(x: 0, y: 0, width: 500, height: 500),
            minimumSize: NSSize(width: 80, height: 80)
        )
        precondition(
            resizeSnap.frame.maxX == 200,
            "Resizing near another widget should snap to the shared gap"
        )
        precondition(resizeSnap.verticalGuide != nil, "A resize snap should provide a guide")

        print("PASS: desktop-widget interaction and spacing behavior")
    }
}
