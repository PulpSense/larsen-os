import Combine
import Foundation

@MainActor
final class DesktopWidgetVisibility: ObservableObject {
    enum Widget: String, CaseIterable {
        case worldClocks = "desktopWorldClockPanelEnabled"
        case deepWork = "desktopConsistencyPanelEnabled"
        case yearElapsed = "desktopYearProgressPanelEnabled"
    }

    static let shared = DesktopWidgetVisibility()

    @Published private var visibleWidgets: Set<Widget>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        visibleWidgets = Set(Widget.allCases.filter {
            defaults.object(forKey: $0.rawValue) == nil || defaults.bool(forKey: $0.rawValue)
        })
    }

    func isVisible(_ widget: Widget) -> Bool {
        visibleWidgets.contains(widget)
    }

    func setVisible(_ visible: Bool, for widget: Widget) {
        defaults.set(visible, forKey: widget.rawValue)
        guard visible != isVisible(widget) else { return }
        if visible {
            visibleWidgets.insert(widget)
        } else {
            visibleWidgets.remove(widget)
        }
    }
}
