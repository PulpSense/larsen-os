import AppKit
import Carbon
import SwiftUI

struct AppShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let timer = AppShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey), key: "J")
    static let checkIn = AppShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey), key: "H")

    var title: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map { $0.1 }.joined() + key
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.intersection([.control, .command]).isEmpty,
              let characters = event.charactersIgnoringModifiers?.uppercased(), characters.count == 1,
              characters.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")) != nil else { return nil }
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if flags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: characters)
    }
}

/// Owns registration and persistence for both app-wide shortcuts. Failed edits preserve the previous binding.
@MainActor
final class GlobalShortcut: ObservableObject {
    static let timer = GlobalShortcut(name: "timer", signature: 0x44574654, defaultShortcut: .timer)
    static let checkIn = GlobalShortcut(name: "checkIn", signature: 0x44574843, defaultShortcut: .checkIn)

    @Published private(set) var isEnabled: Bool
    @Published private(set) var combination: AppShortcut
    @Published private(set) var errorMessage: String?
    private let name: String
    private let signature: OSType
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    private init(name: String, signature: OSType, defaultShortcut: AppShortcut) {
        self.name = name
        self.signature = signature
        isEnabled = UserDefaults.standard.object(forKey: "\(name)ShortcutEnabled") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: "\(name)Shortcut.v2"),
           let saved = try? JSONDecoder().decode(AppShortcut.self, from: data) {
            combination = saved
        } else {
            // Adopt the new right-hand defaults while retaining explicitly selected legacy alternatives.
            let legacy = UserDefaults.standard.string(forKey: "checkInShortcutCombination")
            if name == "checkIn", legacy == "controlOptionH" || legacy == "commandOptionH" {
                combination = AppShortcut(keyCode: UInt32(kVK_ANSI_H),
                    modifiers: UInt32(legacy == "controlOptionH" ? controlKey | optionKey : cmdKey | optionKey), key: "H")
            } else { combination = defaultShortcut }
        }
    }

    func start(action: @escaping () -> Void) {
        self.action = action
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == owner.signature, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor in owner.action?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { errorMessage = "Couldn’t enable the shortcut."; return }
        registerCurrent()
    }

    func setEnabled(_ enabled: Bool) {
        unregister()
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "\(name)ShortcutEnabled")
        registerCurrent()
    }

    func setCombination(_ shortcut: AppShortcut) {
        let previous = combination
        unregister()
        combination = shortcut
        registerCurrent()
        if let error = errorMessage {
            combination = previous
            registerCurrent()
            errorMessage = error
        } else if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "\(name)Shortcut.v2")
        }
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func registerCurrent() {
        errorMessage = nil
        guard isEnabled, handler != nil else { return }
        let status = RegisterEventHotKey(combination.keyCode, combination.modifiers,
            EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive), &hotKey)
        if status != noErr { errorMessage = "\(combination.title) is unavailable. Choose another shortcut." }
    }

    static func suspendRecording() { timer.unregister(); checkIn.unregister() }
    static func resumeRecording() { timer.registerCurrent(); checkIn.registerCurrent() }
}

/// A single owner prevents two settings rows from recording the same keystroke.
@MainActor
final class ShortcutRecordingSession: ObservableObject {
    static let shared = ShortcutRecordingSession()
    @Published private(set) var shortcut: GlobalShortcut?
    private var monitor: Any?

    func begin(_ shortcut: GlobalShortcut) {
        stop()
        self.shortcut = shortcut
        GlobalShortcut.suspendRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let shortcut = self.shortcut else { return event }
            if event.keyCode == kVK_Escape { self.stop(); return nil }
            guard let combination = AppShortcut(event: event) else { return nil }
            self.stop()
            shortcut.setCombination(combination)
            return nil
        }
    }

    func stop(ifOwnedBy owner: GlobalShortcut? = nil) {
        if let owner, shortcut !== owner { return }
        guard shortcut != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        shortcut = nil
        GlobalShortcut.resumeRecording()
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var shortcut: GlobalShortcut
    @ObservedObject private var session = ShortcutRecordingSession.shared
    private var recording: Bool { session.shortcut === shortcut }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(recording ? "Press shortcut…" : shortcut.combination.title) {
                if recording { session.stop(ifOwnedBy: shortcut) } else { session.begin(shortcut) }
            }
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 130)
            .disabled(!shortcut.isEnabled)
            .accessibilityLabel(recording ? "Press your shortcut. Escape cancels." : "Change shortcut, \(shortcut.combination.title)")
            if recording {
                Text("Control or Command + letter or number. Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { session.stop(ifOwnedBy: shortcut) }
    }
}
