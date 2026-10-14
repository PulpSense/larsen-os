import AppKit

enum FocusTimerPresentationTests {
    @MainActor
    static func runChecks() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = FocusTimerController.shared
        // Drive local events explicitly; clicks in unrelated apps must not interrupt this test.
        controller.install(observeExternalClicks: false)
        controller.reset()
        controller.startDefaultOrShow()
        let neighbor = NSStatusBar.system.statusItem(withLength: 24)
        neighbor.button?.title = "·"
        defer { NSStatusBar.system.removeStatusItem(neighbor) }
        try? await Task.sleep(for: .milliseconds(400))
        let initialStatus = app.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
        precondition(initialStatus.contains { $0.isVisible && $0.frame.height > 0 }, "Initial timer must be rendered before testing reattachment.")
        let initialTimerWindow = initialStatus.first { $0.isVisible && $0.frame.width > 70 }!
        let wasRightOfNeighbor = initialTimerWindow.frame.minX > neighbor.button!.window!.frame.minX
        precondition(controller.session.phase == .running && controller.session.duration == 3_600)
        controller.pauseOrResume()
        precondition(controller.session.phase == .paused)
        let remainder = controller.session.remaining(at: Date())
        controller.detach()
        // Include a countdown tick to catch hidden status items resurfacing during image updates.
        try? await Task.sleep(for: .milliseconds(1_100))
        let panel = app.windows.first { $0.title == "Focus timer" && $0.isVisible }!
        precondition(panel.frame.size == NSSize(width: 220, height: 28))
        precondition(panel.level == .screenSaver)
        precondition(panel.collectionBehavior.contains(.canJoinAllSpaces))
        precondition(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        precondition(!panel.hidesOnDeactivate)
        precondition(controller.session.remaining(at: Date()) == remainder)
        precondition(initialTimerWindow.frame.width <= 16,
                     "Detaching must collapse the retained menu bar item.")
        controller.attach()
        try? await Task.sleep(for: .milliseconds(400))
        let statusWindows = app.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
        precondition(statusWindows.contains { window in
            window.isVisible && window.frame.width > 0 && window.frame.height > 0
        },
                     "Reattaching must restore a visible menu bar timer, not just close the floating panel.")
        let attachedTimerWindow = statusWindows.first { $0.isVisible && $0.frame.width > 70 }!
        precondition(attachedTimerWindow === initialTimerWindow,
                     "Detaching must preserve the existing status item and its custom menu bar placement.")
        precondition((attachedTimerWindow.frame.minX > neighbor.button!.window!.frame.minX) == wasRightOfNeighbor,
                     "Attaching must restore the timer’s order relative to neighboring menu bar items.")
        precondition(!panel.isVisible)
        precondition(controller.session.phase == .paused)
        controller.pauseOrResume()
        precondition(controller.session.phase == .running)
        controller.start(minutes: 10)
        let finish = controller.session.deadline!
        controller.refresh(at: finish)
        precondition(controller.session.phase == .completed)
        precondition(attachedTimerWindow.frame.width > 16)
        controller.refresh(at: finish.addingTimeInterval(29))
        precondition(controller.session.phase == .completed)
        controller.refresh(at: finish.addingTimeInterval(30))
        precondition(controller.session.phase == .idle)
        try? await Task.sleep(for: .milliseconds(400))
        precondition(attachedTimerWindow.frame.width <= 16, "Done must stop taking menu bar space after 30 seconds.")
        controller.presentLauncher()
        try? await Task.sleep(for: .milliseconds(200))
        let launcher = app.windows.first { $0.title == "Start timer" && $0.isVisible }!
        precondition(launcher.canBecomeKey && launcher.level == .screenSaver)
        precondition(controller.session.phase == .idle, "Opening the input bar must not start a timer.")
        func press(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) async {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: launcher.windowNumber, context: nil,
                                        characters: characters, charactersIgnoringModifiers: characters,
                                        isARepeat: false, keyCode: keyCode)!
            app.postEvent(event, atStart: false)
            try? await Task.sleep(for: .milliseconds(100))
        }
        await press("\t", keyCode: 48)
        await press("2", keyCode: 19, modifiers: .command)
        await press("\r", keyCode: 36)
        precondition(controller.session.phase == .running && controller.session.kind == .break)
        precondition(controller.session.duration == 900, "Tab, Command-2 and Return must configure and start a break without a mouse.")
        precondition(!launcher.isVisible)
        controller.reset()
        controller.start(minutes: 15)
        try? await Task.sleep(for: .milliseconds(400))
        precondition(attachedTimerWindow.isVisible && attachedTimerWindow.frame.width > 16)
        precondition(controller.session.duration == 900)
        precondition((attachedTimerWindow.frame.minX > neighbor.button!.window!.frame.minX) == wasRightOfNeighbor,
                     "Starting after automatic dismissal must preserve the menu bar order.")
        controller.pauseOrResume()
        controller.complete()
        precondition(controller.session.phase == .completed && controller.session.completedAt != nil)
        precondition(app.windows.contains { $0.title == "Timer completed" && $0.isVisible })
        controller.reset()
        controller.previewAlert()
        let alerts = app.windows.filter { $0.title == "Timer completed" && $0.isVisible }
        precondition(alerts.count == NSScreen.screens.count)
        precondition(alerts.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey && $0.level == .screenSaver })
        precondition(controller.session.phase == .idle, "Previewing must not start or complete a session.")
        try? await Task.sleep(for: .milliseconds(3_200))
        precondition(alerts.allSatisfy { !$0.isVisible }, "The halo and banner must close after three seconds.")
        controller.start(minutes: 10, kind: .break)
        let breakFinish = controller.session.deadline!
        controller.refresh(at: breakFinish)
        let breakAlerts = app.windows.filter { $0.title == "Break completed" && $0.isVisible }
        precondition(breakAlerts.count == NSScreen.screens.count)
        precondition(breakAlerts.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey })
        try? await Task.sleep(for: .milliseconds(3_200))
        precondition(breakAlerts.allSatisfy { $0.isVisible }, "Break banners must outlast the halo; phase=\(controller.session.phase).")
        controller.refresh(at: breakFinish.addingTimeInterval(60))
        precondition(controller.session.phase == .completed, "Break completion must wait for acknowledgement.")
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 1)!
        app.postEvent(click, atStart: false)
        try? await Task.sleep(for: .milliseconds(300))
        precondition(controller.session.phase == .idle, "Clicking anywhere must dismiss a completed break.")
        precondition(breakAlerts.allSatisfy { !$0.isVisible })
        print("Focus timer presentation tests passed: default start, pause, detach, window level, attach, resume, cancel, non-interactive completion alert and three-second dismissal")
    }
}

@MainActor
final class FocusTimerPresentationTestDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await FocusTimerPresentationTests.runChecks()
            NSApp.terminate(nil)
        }
    }
}
@main
enum FocusTimerPresentationTestRunner {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FocusTimerPresentationTestDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
