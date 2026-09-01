import ServiceManagement
import SwiftUI

@main
struct DigitalWallApp: App {
    @NSApplicationDelegateAdaptor(DigitalWallAppDelegate.self) private var appDelegate
    @StateObject private var store = WallStore()

    var body: some Scene {
        Window("Digital Wall", id: "main") {
            DashboardView(store: store)
                .frame(minWidth: 820, minHeight: 600)
                .onAppear {
                    PhraseDesktopPanelController.shared.restoreIfEnabled(store: store)
                    VisionBoardDesktopPanelController.shared.restoreIfEnabled(store: store)
                    ConsistencyDesktopPanelController.shared.restoreIfEnabled(store: store)
                    YearProgressDesktopPanelController.shared.restoreIfEnabled()
                    WorldClockDesktopPanelController.shared.restoreIfEnabled(store: store)
                }
                .onOpenURL { url in
                    guard url.scheme == AppConfiguration.urlScheme else { return }
                    switch url.host {
                    case "show-phrase-panel":
                        PhraseDesktopPanelController.shared.present(store: store)
                    case "show-vision-panel":
                        VisionBoardDesktopPanelController.shared.present(store: store)
                    case "show-consistency-panel":
                        ConsistencyDesktopPanelController.shared.present(store: store)
                    case "show-year-progress":
                        YearProgressDesktopPanelController.shared.present()
                    case "show-world-clocks":
                        WorldClockDesktopPanelController.shared.present(store: store)
                    default:
                        let boardID = store.visionBoards.first?.id
                        VisionBoardPresenter.shared.present(
                            images: boardID.map { store.images(for: $0) } ?? [],
                            hideApplicationOnDismiss: true
                        )
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Show Vision Board") {
                    let boardID = store.visionBoards.first?.id
                    VisionBoardPresenter.shared.present(
                        images: boardID.map { store.images(for: $0) } ?? []
                    )
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Show Desktop Phrase Panel") {
                    PhraseDesktopPanelController.shared.present(store: store)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("New Desktop Phrase Window") {
                    _ = PhraseDesktopPanelController.shared.createAndPresent(store: store)
                }

                Button("Show Desktop Vision Board") {
                    VisionBoardDesktopPanelController.shared.present(store: store)
                }

                Button("New Vision Board") {
                    VisionBoardDesktopPanelController.shared.createAndPresent(store: store)
                }

                Button("Show Desktop Consistency") {
                    ConsistencyDesktopPanelController.shared.present(store: store)
                }

                Button("Show Year Progress") {
                    YearProgressDesktopPanelController.shared.present()
                }

                Button("Show Desktop World Clocks") {
                    WorldClockDesktopPanelController.shared.present(store: store)
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class DigitalWallAppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAsLoginItem = NSAppleEventManager.shared()
            .currentAppleEvent?
            .paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?
            .booleanValue ?? false

        if launchedAsLoginItem {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        LaunchAtLoginController.shared.prepareInstalledApp()

        if launchedAsLoginItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                NSApp.windows
                    .filter { !($0 is NSPanel) && $0.canBecomeMain }
                    .forEach { $0.orderOut(nil) }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        sender.windows
            .filter { !($0 is NSPanel) && $0.canBecomeMain }
            .forEach { $0.makeKeyAndOrderFront(nil) }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window.canBecomeMain else { return }

        DispatchQueue.main.async {
            let hasVisibleMainWindow = NSApp.windows.contains {
                !($0 is NSPanel) && $0.canBecomeMain && $0.isVisible
            }
            if !hasVisibleMainWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

private struct SettingsView: View {
    @StateObject private var launchAtLogin = LaunchAtLoginController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Private by design", systemImage: "lock.fill")
                .font(.headline)
            Text("Your images, phrases, and consistency history stay on this Mac.")
                .foregroundStyle(.secondary)

            Divider()

            Toggle(
                "Open Digital Wall at login",
                isOn: Binding(
                    get: { launchAtLogin.isRequested },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            Text("Starts quietly, restores your desktop panels, and stays out of the Dock.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if launchAtLogin.requiresApproval {
                HStack {
                    Text("macOS needs your approval before it can start automatically.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Login Items") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            if let errorMessage = launchAtLogin.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

@MainActor
private final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()

    @Published private(set) var isRequested: Bool
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    private let preferenceKey = "launchAtLoginRequested"
    private let service = SMAppService.mainApp

    private init() {
        let defaults = UserDefaults.standard
        isRequested = defaults.object(forKey: preferenceKey) as? Bool
            ?? (service.status == .enabled || service.status == .requiresApproval)
        refreshStatus()
    }

    func prepareInstalledApp() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            refreshStatus()
            return
        }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: preferenceKey) == nil {
            defaults.set(true, forKey: preferenceKey)
            isRequested = true
        }

        if isRequested,
           service.status != .enabled,
           service.status != .requiresApproval {
            register()
        } else {
            refreshStatus()
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        isRequested = enabled
        errorMessage = nil

        if enabled {
            register()
        } else {
            unregister()
        }
    }

    private func register() {
        do {
            if service.status != .enabled, service.status != .requiresApproval {
                try service.register()
            }
        } catch {
            errorMessage = "Couldn’t enable launch at login: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    private func unregister() {
        do {
            if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            errorMessage = "Couldn’t disable launch at login: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    private func refreshStatus() {
        requiresApproval = service.status == .requiresApproval
    }
}
