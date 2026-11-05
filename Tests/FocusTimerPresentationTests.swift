import AppKit

enum FocusTimerPresentationTests {
    @MainActor
    static func runChecks() async {
        func waitUntil(_ condition: () -> Bool) async {
            let deadline = Date().addingTimeInterval(5)
            while !condition() && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let originalAction = UserDefaults.standard.object(forKey: CheckInFlowPreferences.timerActionKey)
        UserDefaults.standard.set(TimerCompletionAction.alert.rawValue, forKey: CheckInFlowPreferences.timerActionKey)
        defer {
            if let originalAction { UserDefaults.standard.set(originalAction, forKey: CheckInFlowPreferences.timerActionKey) }
            else { UserDefaults.standard.removeObject(forKey: CheckInFlowPreferences.timerActionKey) }
        }
        let controller = FocusTimerController.shared
        // Drive local events explicitly; clicks in unrelated apps must not interrupt this test.
        controller.install(observeExternalClicks: false)
        controller.attach()
        controller.reset()
        let input = TimerLauncherInput()
        precondition(input.kind == .timer)
        input.text = "29m"
        precondition(input.kind == .break)
        input.text = "30m"
        precondition(input.kind == .timer)
        input.setDuration(10)
        precondition(input.kind == .break)
        input.toggleKind()
        input.setDuration(15)
        precondition(input.kind == .timer, "Explicit mode override must survive duration edits")
        let explicitTimer = TimerLauncherInput()
        explicitTimer.text = "10 minute timer"
        precondition(explicitTimer.kind == .timer)
        explicitTimer.text = "45 minute break"
        precondition(explicitTimer.kind == .break)
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
        precondition(panel.frame.size == NSSize(width: 260, height: 36))
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
        controller.detach()
        controller.reset()
        precondition(UserDefaults.standard.bool(forKey: "focusTimerDetached"), "Cancel must preserve detached preference")
        controller.start(minutes: 1, completionAction: .alert)
        precondition(app.windows.contains { $0.title == "Focus timer" && $0.isVisible }, "New timer must restore detached mode")
        controller.refresh(at: controller.session.deadline!.addingTimeInterval(31))
        precondition(UserDefaults.standard.bool(forKey: "focusTimerDetached"), "Automatic cleanup must preserve detached preference")
        controller.start(minutes: 1, completionAction: .alert)
        precondition(app.windows.contains { $0.title == "Focus timer" && $0.isVisible })
        controller.attach()
        controller.reset()
        controller.start(minutes: 1, completionAction: .alert)
        precondition(!app.windows.contains { $0.title == "Focus timer" && $0.isVisible }, "Explicit attach must become the preference")
        controller.reset()
        controller.previewAlert()
        let alerts = app.windows.filter { $0.title == "Timer completed" && $0.isVisible }
        precondition(alerts.count == NSScreen.screens.count)
        precondition(alerts.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey && $0.level == .screenSaver })
        precondition(controller.session.phase == .idle, "Previewing must not start or complete a session.")
        await waitUntil { alerts.allSatisfy { !$0.isVisible } }
        precondition(alerts.allSatisfy { !$0.isVisible }, "The halo and banner must close after three seconds.")
        controller.start(minutes: 10, kind: .break)
        let breakFinish = controller.session.deadline!
        controller.refresh(at: breakFinish)
        let breakAlerts = app.windows.filter { $0.title == "Break completed" && $0.isVisible }
        precondition(breakAlerts.count == NSScreen.screens.count)
        precondition(breakAlerts.allSatisfy { !$0.ignoresMouseEvents && $0.canBecomeKey })
        precondition(breakAlerts.allSatisfy { $0.frame == $0.screen?.frame },
                     "Break completion must fill each display.")
        try? await Task.sleep(for: .milliseconds(3_200))
        precondition(breakAlerts.allSatisfy { $0.isVisible }, "Break banners must outlast the halo; phase=\(controller.session.phase).")
        controller.refresh(at: breakFinish.addingTimeInterval(60))
        precondition(controller.session.phase == .completed, "Break completion must wait for acknowledgement.")
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 1)!
        app.postEvent(click, atStart: false)
        try? await Task.sleep(for: .milliseconds(300))
        precondition(controller.session.phase == .completed,
                     "Unrelated clicks must not clear the full-screen break reminder.")
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: app.keyWindow!.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        app.sendEvent(returnKey)
        try? await Task.sleep(for: .milliseconds(300))
        precondition(controller.session.phase == .running && controller.session.duration == 3_600,
                     "Return on the break completion page must start another hour.")
        precondition(breakAlerts.allSatisfy { !$0.isVisible })
        controller.refresh(at: controller.session.deadline!)
        precondition(controller.suggestsBreak, "Completing an hour must suggest a break.")
        controller.reset()
        precondition(controller.suggestsBreak, "Acknowledging a completed hour must preserve the suggestion.")
        let suggestedInput = TimerLauncherInput(suggestsBreak: controller.suggestsBreak)
        precondition(suggestedInput.minutes == 10 && suggestedInput.kind == .break)
        suggestedInput.setDuration(60)
        precondition(suggestedInput.minutes == 60 && suggestedInput.kind == .timer)
        controller.presentLauncher()
        try? await Task.sleep(for: .milliseconds(200))
        let hourAlternative = app.keyWindow!
        precondition(hourAlternative.frame.height == 222, "Break suggestion must also show the second hour option.")
        let chooseHour = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: hourAlternative.windowNumber, context: nil,
            characters: "3", charactersIgnoringModifiers: "3", isARepeat: false, keyCode: 20)!
        app.postEvent(chooseHour, atStart: false)
        func durationField(in view: NSView?) -> NSTextField? {
            if let field = view as? NSTextField { return field }
            return view?.subviews.lazy.compactMap { durationField(in: $0) }.first
        }
        await waitUntil { durationField(in: hourAlternative.contentView)?.stringValue == "60 minutes" }
        precondition(durationField(in: hourAlternative.contentView)?.stringValue == "60 minutes",
                     "Command-3 must fill the hour alternative.")
        let submitHour = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: hourAlternative.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        app.postEvent(submitHour, atStart: false)
        await waitUntil { controller.session.phase == .running }
        precondition(controller.session.phase == .running && controller.session.kind == .timer && controller.session.duration == 3_600,
                     "Command-3 and Return must start the hour alternative from the suggested launcher: \(controller.session.phase), \(controller.session.kind), \(controller.session.duration).")
        controller.refresh(at: controller.session.deadline!)
        controller.presentLauncher()
        try? await Task.sleep(for: .milliseconds(200))
        let breakLauncher = app.keyWindow!
        let submitBreak = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: breakLauncher.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        app.sendEvent(submitBreak)
        try? await Task.sleep(for: .milliseconds(200))
        precondition(controller.session.phase == .running && controller.session.kind == .break && controller.session.duration == 600,
                     "The launcher's default after an hour must start a ten-minute break.")
        precondition(!controller.suggestsBreak)
        controller.refresh(at: controller.session.deadline!)
        let dismissWithKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: app.keyWindow!.windowNumber, context: nil,
            characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7)!
        app.postEvent(dismissWithKey, atStart: false)
        try? await Task.sleep(for: .milliseconds(200))
        precondition(controller.session.phase == .idle,
                     "Any ordinary key must dismiss the break completion screen.")
        precondition(!app.windows.contains { $0.title == "Break completed" && $0.isVisible })
        controller.reset()
        var transitions: [Bool?] = []
        controller.configure { transitions.append($0) }
        for action in TimerCompletionAction.allCases {
            controller.reset()
            transitions.removeAll()
            controller.start(minutes: 1, completionAction: action)
            let deadline = controller.session.deadline!
            controller.refresh(at: deadline)
            precondition(transitions.isEmpty, "Expiration must never open a form")
            if action != .alert {
                let completionAlerts = app.windows.filter { $0.title == "Timer completed" && $0.isVisible }
                precondition(completionAlerts.count == NSScreen.screens.count,
                             "Check-in timers must retain the green completion glow on every display")
                precondition(completionAlerts.allSatisfy { $0.ignoresMouseEvents && !$0.canBecomeKey },
                             "Completion glow must leave focus and clicks with the current app")
                controller.refresh(at: deadline.addingTimeInterval(3_600))
                precondition(controller.session.hasPendingCheckIn && controller.session.isIndicatorVisible(at: deadline.addingTimeInterval(3_600)),
                             "A completed timer must stay available until clicked")
                controller.configure { transitions.append($0) }
                precondition(transitions.isEmpty, "Configuring after launch must not open a pending form")
                controller.show()
                precondition(transitions.count == 1 && transitions[0] == (action == .formAndVisionBoard))
                precondition(controller.session.phase == .idle, "Clicking acknowledges the timer")
                controller.refresh()
                precondition(transitions.count == 1, "Acknowledged timer must not repeat the transition")
            }
        }
        controller.reset()
        transitions.removeAll()
        UserDefaults.standard.set(TimerCompletionAction.form.rawValue, forKey: CheckInFlowPreferences.timerActionKey)
        controller.start(minutes: 1)
        UserDefaults.standard.set(TimerCompletionAction.formAndVisionBoard.rawValue, forKey: CheckInFlowPreferences.timerActionKey)
        controller.pauseOrResume()
        controller.complete()
        precondition(transitions.isEmpty, "Manual completion must also wait for a click")
        controller.detach()
        controller.show()
        precondition(transitions.count == 1 && transitions[0] == false,
                     "Clicking the detached timer must preserve its session choice")
        controller.reset()
        transitions.removeAll()
        controller.start(minutes: 1, kind: .break, completionAction: .formAndVisionBoard)
        controller.complete()
        precondition(transitions.isEmpty, "Break completion must never open a form")
        controller.reset()
        controller.finishHour()
        precondition(transitions.count == 1 && transitions[0] == nil, "Manual check-ins use their own setting")
        controller.reset()
        print("PASS: no intrusive form on completion or configure, click to continue, persistent pending indicator, detached timer, and per-session choices")
        print("Focus timer presentation tests passed: default start, pause, detach, window level, attach, resume, cancel, work completion glow, break suggestion, persistent full-screen break completion and Return to restart")
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
