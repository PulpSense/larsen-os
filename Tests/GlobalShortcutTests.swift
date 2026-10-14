import AppKit
import Carbon

@main
enum GlobalShortcutTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let timer = GlobalShortcut.timer
        let checkIn = GlobalShortcut.checkIn
        timer.start {}
        checkIn.start {}
        precondition(timer.combination == .timer && timer.combination.title == "⌃J")
        precondition(checkIn.combination == .checkIn && checkIn.combination.title == "⌃H")
        if let error = timer.errorMessage ?? checkIn.errorMessage { FileHandle.standardError.write(Data((error + "\n").utf8)) }
        precondition(timer.errorMessage == nil && checkIn.errorMessage == nil)
        let changed = AppShortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey), key: "L")
        timer.setCombination(changed)
        precondition(timer.combination == changed && timer.errorMessage == nil)
        let saved = UserDefaults.standard.data(forKey: "timerShortcut.v2")!
        let restored = try JSONDecoder().decode(AppShortcut.self, from: saved)
        precondition(restored == changed)
        timer.setCombination(checkIn.combination)
        precondition(timer.combination == changed && timer.errorMessage != nil,
                     "A conflict must retain the previous binding.")
        precondition(UserDefaults.standard.data(forKey: "timerShortcut.v2") == saved)
        let recording = ShortcutRecordingSession.shared
        recording.begin(timer)
        precondition(recording.shortcut === timer)
        recording.begin(checkIn)
        precondition(recording.shortcut === checkIn, "Starting another recorder must replace the previous owner.")
        recording.stop(ifOwnedBy: timer)
        precondition(recording.shortcut === checkIn, "A stale recorder must not cancel the active recorder.")
        recording.stop(ifOwnedBy: checkIn)
        precondition(recording.shortcut == nil)
        GlobalShortcut.suspendRecording()
        GlobalShortcut.resumeRecording()
        precondition(timer.errorMessage == nil && checkIn.errorMessage == nil)
        timer.setEnabled(false)
        precondition(!timer.isEnabled)
        timer.setEnabled(true)
        precondition(timer.isEnabled && timer.errorMessage == nil)
        timer.setCombination(.timer)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control,
            timestamp: 0, windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: UInt16(kVK_ANSI_J))!
        precondition(AppShortcut(event: event) == .timer)
        let option = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option,
            timestamp: 0, windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: UInt16(kVK_ANSI_J))!
        precondition(AppShortcut(event: option) == nil, "Option-only shortcuts must be rejected.")
        timer.setEnabled(false)
        checkIn.setEnabled(false)
        for key in ["timerShortcut.v2", "checkInShortcut.v2", "timerShortcutEnabled", "checkInShortcutEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        print("Shortcut tests passed: right-hand defaults, recording, persistence, conflicts, suspend/resume and enable/disable")
    }
}
