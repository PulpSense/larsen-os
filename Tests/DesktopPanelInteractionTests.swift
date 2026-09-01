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

        print("PASS: desktop-panel drag behavior follows edit mode")
    }
}
