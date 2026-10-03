import AppKit
import Carbon
import SwiftUI

enum CheckInShortcutCombination: String, CaseIterable, Identifiable {
    case commandShiftH, controlOptionH, commandOptionH
    var id: Self { self }
    var title: String {
        switch self {
        case .commandShiftH: "⌘⇧H"
        case .controlOptionH: "⌃⌥H"
        case .commandOptionH: "⌘⌥H"
        }
    }
    var modifiers: UInt32 {
        switch self {
        case .commandShiftH: UInt32(cmdKey | shiftKey)
        case .controlOptionH: UInt32(controlKey | optionKey)
        case .commandOptionH: UInt32(cmdKey | optionKey)
        }
    }
}

@MainActor
final class CheckInShortcut: ObservableObject {
    static let shared = CheckInShortcut()
    @Published private(set) var isEnabled: Bool
    @Published private(set) var combination: CheckInShortcutCombination
    @Published private(set) var errorMessage: String?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "checkInShortcutEnabled") as? Bool ?? true
        combination = CheckInShortcutCombination(rawValue:
            UserDefaults.standard.string(forKey: "checkInShortcutCombination") ?? ""
        ) ?? .commandShiftH
    }

    func start(action: @escaping () -> Void) {
        self.action = action
        if handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard result == noErr, identifier.signature == 0x44574843, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                Task { @MainActor in CheckInShortcut.shared.action?() }
                return noErr
            }, 1, &eventType, nil, &handler)
            guard result == noErr else {
                errorMessage = "Couldn’t install the global shortcut (\(result))."
                return
            }
        }
        register()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "checkInShortcutEnabled")
        register()
    }

    func setCombination(_ combination: CheckInShortcutCombination) {
        self.combination = combination
        UserDefaults.standard.set(combination.rawValue, forKey: "checkInShortcutCombination")
        register()
    }

    private func register() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        errorMessage = nil
        guard isEnabled, handler != nil else { return }
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_H), combination.modifiers,
            EventHotKeyID(signature: 0x44574843, id: 1), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey)
        if result != noErr {
            errorMessage = "This shortcut is unavailable (\(result)). Choose another combination."
        }
    }
}
