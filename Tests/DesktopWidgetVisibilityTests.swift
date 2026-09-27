import Combine
import Foundation

@main
enum DesktopWidgetVisibilityTests {
    @MainActor
    static func main() {
        let suiteName = "DigitalWallVisibilityTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let visibility = DesktopWidgetVisibility(defaults: defaults)
        for widget in DesktopWidgetVisibility.Widget.allCases {
            precondition(visibility.isVisible(widget), "Existing first-launch behavior should show every widget")
        }

        var notifications = 0
        let subscription = visibility.objectWillChange.sink { notifications += 1 }
        defer { subscription.cancel() }

        visibility.setVisible(false, for: .worldClocks)
        visibility.setVisible(false, for: .yearElapsed)
        precondition(!visibility.isVisible(.worldClocks))
        precondition(!visibility.isVisible(.yearElapsed))
        precondition(visibility.isVisible(.deepWork), "Each widget needs independent visibility")
        precondition(notifications == 2, "Widget menus and app toggles need observable state changes")

        let relaunched = DesktopWidgetVisibility(defaults: defaults)
        precondition(!relaunched.isVisible(.worldClocks) && !relaunched.isVisible(.yearElapsed))
        precondition(relaunched.isVisible(.deepWork), "Hiding a widget must survive relaunch")

        visibility.setVisible(true, for: .worldClocks)
        precondition(defaults.bool(forKey: DesktopWidgetVisibility.Widget.worldClocks.rawValue))
        precondition(DesktopWidgetVisibility(defaults: defaults).isVisible(.worldClocks))
        precondition(notifications == 3)
        print("PASS: desktop widget visibility is synchronized and survives relaunch")
    }
}
