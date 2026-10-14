import AppKit
import Carbon
import SwiftUI

@MainActor
final class FocusTimerController: NSObject, ObservableObject {
    static let shared = FocusTimerController()

    @Published private(set) var session = FocusTimer()
    @Published private(set) var now = Date()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var detachedPanel: NSPanel?
    private var launcherPanel: TimerLauncherPanel?
    private var launcherMonitors: [Any] = []
    private var launcherPreviousApplication: NSRunningApplication?
    private weak var launcherPreviousKeyWindow: NSWindow?
    private var ticker: Timer?
    private let glow = TimerCompletionGlow()
    private let storageKey = "focusTimerSession.v1"
    private var checkIn: (() -> Void)?
    private var observesExternalClicks = true

    func configure(checkIn: @escaping () -> Void) { self.checkIn = checkIn }

    func install(observeExternalClicks: Bool = true) {
        guard ticker == nil else { return }
        observesExternalClicks = observeExternalClicks
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(FocusTimer.self, from: data) {
            session = saved
        }
        createStatusItem()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: FocusTimerPopover(controller: self))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        GlobalShortcut.timer.start { [weak self] in self?.presentLauncher() }
        if UserDefaults.standard.bool(forKey: "focusTimerDetached"), session.isIndicatorVisible(at: Date()) {
            detach()
        }
        refresh()
        if session.phase == .completed, session.kind == .break {
            presentCompletion(playSound: false)
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 72)
        item.autosaveName = "FocusTimer"
        item.isVisible = true
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        renderIcon()
    }

    /// Starts only when no session is active, so pressing the shortcut twice never loses progress.
    func startDefaultOrShow() {
        if session.phase == .idle || session.phase == .completed { start(minutes: 60) }
        else { show() }
    }

    func presentLauncher() {
        if let launcherPanel, launcherPanel.isVisible {
            launcherPanel.makeKeyAndOrderFront(nil)
            return
        }
        popover.performClose(nil)
        launcherPreviousApplication = NSWorkspace.shared.frontmostApplication
        launcherPreviousKeyWindow = NSApp.keyWindow
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let width = min(500, screen.visibleFrame.width - 32)
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2,
                           y: screen.visibleFrame.midY + screen.visibleFrame.height * 0.18,
                           width: width, height: 164)
        let panel = TimerLauncherPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.title = "Start timer"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.dismissAction = { [weak self] in self?.dismissLauncher() }
        let input = TimerLauncherInput()
        panel.contentView = NSHostingView(rootView: TimerDurationLauncher(controller: self, input: input))
        launcherPanel = panel
        panel.makeKeyAndOrderFront(nil)
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak panel, weak input] event in
            guard let panel, event.window === panel, let input else { return event }
            if event.keyCode == 48 && event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                input.toggleKind()
                return nil
            }
            if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
               let key = event.charactersIgnoringModifiers,
               let index = ["1", "2", "3"].firstIndex(of: key) {
                input.setDuration([10, 15, 60][index])
                return nil
            }
            return event
        }) { launcherMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let self, event.window !== self.launcherPanel { self.dismissLauncher(restoringFocus: false) }
            return event
        }) { launcherMonitors.append(monitor) }
        if observesExternalClicks, let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.dismissLauncher(restoringFocus: false) }
        }) { launcherMonitors.append(monitor) }
    }

    func dismissLauncher(restoringFocus: Bool = true) {
        guard launcherPanel != nil else { return }
        launcherMonitors.forEach { NSEvent.removeMonitor($0) }
        launcherMonitors.removeAll()
        launcherPanel?.close()
        launcherPanel = nil
        if restoringFocus {
            if let application = launcherPreviousApplication,
               application.processIdentifier != ProcessInfo.processInfo.processIdentifier { application.activate() }
            else { launcherPreviousKeyWindow?.makeKey() }
        }
        launcherPreviousApplication = nil
        launcherPreviousKeyWindow = nil
    }

    var durationText: String {
        let minutes = Int(session.duration / 60)
        return minutes == 60 ? "1 hour" : "\(minutes) minutes"
    }

    var remainingText: String {
        let seconds = Int(ceil(session.remaining(at: now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func start(minutes: Int, kind: FocusTimer.Kind = .timer) {
        glow.dismiss()
        session.start(minutes: minutes, kind: kind, at: Date())
        save()
        refresh()
        popover.performClose(nil)
        dismissLauncher()
    }

    func pauseOrResume() {
        refresh()
        if session.phase == .running { session.pause(at: now) }
        else if session.phase == .paused { session.resume(at: now) }
        save()
        renderIcon()
    }

    func complete() {
        now = Date()
        guard session.complete(at: now) else { return }
        save()
        popover.performClose(nil)
        presentCompletion()
        renderIcon()
    }

    func reset() {
        glow.dismiss()
        session.reset()
        attach()
        save()
        refresh()
    }

    func finishHour() {
        popover.performClose(nil)
        reset()
        checkIn?()
    }

    func previewAlert() { glow.present() }

    private func presentCompletion(playSound: Bool = true) {
        let isBreak = session.kind == .break
        if isBreak && playSound { NSSound(named: "Glass")?.play() }
        glow.present(persistent: isBreak, observeExternalClicks: observesExternalClicks, onDismiss: { [weak self] in self?.reset() })
    }

    @objc private func didWake() { refresh() }

    func show() {
        refresh()
        if !session.isIndicatorVisible(at: now) { presentLauncher(); return }
        if session.phase == .running || session.phase == .paused {
            showSessionMenu()
            return
        }
        if detachedPanel != nil { attach() }
        guard let button = statusItem?.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { show() }
    }

    private func showSessionMenu() {
        let menu = NSMenu()
        menu.minimumWidth = 260
        let heading = NSMenuItem()
        heading.view = NSHostingView(rootView: VStack(alignment: .leading, spacing: 4) {
            Text(session.kind == .break ? "Break" : "Timer").font(.system(size: 14, weight: .semibold))
            Text(durationText).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14))
        heading.view?.frame = NSRect(x: 0, y: 0, width: 260, height: 60)
        menu.addItem(heading)
        menu.addItem(.separator())
        func add(_ title: String, symbol: String, action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        add(session.phase == .paused ? "Resume" : "Pause",
            symbol: session.phase == .paused ? "play.fill" : "pause.fill", action: #selector(menuPause))
        add("Complete", symbol: "checkmark.circle", action: #selector(menuComplete))
        add("Cancel", symbol: "xmark.circle", action: #selector(menuCancel))
        menu.addItem(.separator())
        add(detachedPanel == nil ? "Detach" : "Attach to menu bar",
            symbol: detachedPanel == nil ? "arrow.down.circle" : "arrow.up.circle", action: #selector(menuDetach))
        if let view = detachedPanel?.contentView ?? statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY), in: view)
        }
    }

    @objc private func menuPause() { pauseOrResume() }
    @objc private func menuComplete() { complete() }
    @objc private func menuCancel() { reset() }
    @objc private func menuDetach() {
        // Wait until menu tracking finishes before hiding its anchor window.
        DispatchQueue.main.async {
            if self.detachedPanel == nil { self.detach() } else { self.attach() }
        }
    }

    func detach() {
        guard detachedPanel == nil, session.phase != .idle else { return }
        popover.performClose(nil)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let rect = NSRect(x: visible.maxX - 240, y: visible.maxY - 56, width: 220, height: 28)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Focus timer"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DetachedFocusTimer(controller: self))
        if let saved = UserDefaults.standard.string(forKey: "focusTimerDetachedOrigin") {
            let origin = NSPointFromString(saved)
            let savedRect = NSRect(origin: origin, size: rect.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(savedRect) }) {
                panel.setFrameOrigin(origin)
            }
        }
        detachedPanel = panel
        panel.orderFrontRegardless()
        // Keep the same item so AppKit retains its user-arranged menu bar position.
        statusItem?.button?.image = nil
        statusItem?.length = 0
        UserDefaults.standard.set(true, forKey: "focusTimerDetached")
    }

    func attach() {
        if statusItem == nil { createStatusItem() }
        statusItem?.length = 72
        statusItem?.isVisible = true
        if let detachedPanel {
            UserDefaults.standard.set(NSStringFromPoint(detachedPanel.frame.origin), forKey: "focusTimerDetachedOrigin")
            detachedPanel.close()
        }
        detachedPanel = nil
        renderIcon()
        UserDefaults.standard.set(false, forKey: "focusTimerDetached")
    }

    func refresh(at date: Date = Date()) {
        now = date
        if session.update(at: now) {
            save()
            presentCompletion()
        }
        if session.phase == .completed, !session.isIndicatorVisible(at: now) {
            session.reset()
            attach()
            save()
            popover.performClose(nil)
        }
        renderIcon()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func renderIcon() {
        guard detachedPanel == nil else { return }
        guard session.isIndicatorVisible(at: now) else {
            statusItem?.button?.image = nil
            statusItem?.length = 0
            return
        }
        statusItem?.length = 72
        let phase = session.phase
        let progress = session.progress(at: now)
        let text = phase == .completed ? "Done" : remainingText
        let image = NSImage(size: NSSize(width: 64, height: 20), flipped: false) { _ in
            let rect = NSRect(x: 0.5, y: 1, width: 63, height: 18)
            let outline = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            outline.fill()
            NSColor.systemGreen.withAlphaComponent(0.65).setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.7).setStroke()
            outline.lineWidth = 1
            outline.stroke()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            let label = NSAttributedString(string: text, attributes: attributes)
            let size = label.size()
            label.draw(at: NSPoint(x: (64 - size.width) / 2, y: (20 - size.height) / 2))
            return true
        }
        image.isTemplate = false
        statusItem?.button?.image = image
        let description: String
        switch phase {
        case .idle: description = "Start a timer (\(GlobalShortcut.timer.combination.title))"
        case .running: description = "Focus timer: \(remainingText) remaining"
        case .paused: description = "Focus timer paused: \(remainingText) remaining"
        case .completed: description = "Timer complete"
        }
        statusItem?.button?.toolTip = description
        statusItem?.button?.setAccessibilityLabel(description)
    }
}

private final class TimerLauncherPanel: NSPanel {
    var dismissAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismissAction?() }
}

/// One keyboard-focused command, shared by the field and the panel's key monitor.
@MainActor
private final class TimerLauncherInput: ObservableObject {
    @Published var text = "" {
        didSet {
            showsError = false
            if TimerDuration.kind(from: text) == .break { kind = .break }
            else if TimerDuration.kind(from: oldValue) == .break { kind = .timer }
        }
    }
    @Published var kind: FocusTimer.Kind = .timer
    @Published var showsError = false
    var minutes: Int? { TimerDuration.minutes(from: text) }

    func toggleKind() { kind = kind == .timer ? .break : .timer }
    func setDuration(_ minutes: Int) {
        let selectedKind = kind
        text = "\(minutes) minutes"
        kind = selectedKind
    }
}

/// A native field becomes first responder as soon as the nonactivating panel opens.
private struct TimerLauncherField: NSViewRepresentable {
    @ObservedObject var input: TimerLauncherInput
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.textColor = .white
        field.placeholderString = "Duration, e.g. 10 minute break"
        field.setAccessibilityLabel("Timer duration")
        field.delegate = context.coordinator
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != input.text { field.stringValue = input.text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimerLauncherField
        init(_ parent: TimerLauncherField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.input.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if command == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            if command == #selector(NSResponder.cancelOperation(_:)) { parent.onCancel(); return true }
            return false
        }
    }
}

private struct TimerDurationLauncher: View {
    @ObservedObject var controller: FocusTimerController
    @ObservedObject var input: TimerLauncherInput

    private var hasActiveTimer: Bool { controller.session.phase == .running || controller.session.phase == .paused }
    private var actionTitle: String {
        let mode = input.kind == .break ? "break" : "timer"
        return "\(hasActiveTimer ? "Replace with" : "Start") \(input.minutes ?? 60) minute \(mode)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                TimerLauncherField(input: input, onSubmit: submit, onCancel: { controller.dismissLauncher() })
                    .frame(height: 28)
                Text("esc").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(4)
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.1)) }
            }
            .padding(.horizontal, 18)
            .frame(height: 60)
            Divider().opacity(0.5)
            Button { submit() } label: {
                HStack(spacing: 12) {
                    Image(systemName: input.kind == .break ? "cup.and.saucer" : "timer")
                        .font(.system(size: 18)).foregroundStyle(.green)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(input.showsError ? "Enter 1–180 minutes" : actionTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(input.showsError ? Color.red : Color.primary)
                        Text(input.kind == .break ? "One chime · stays until you click" : "Green halo · clears automatically")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "return").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(input.showsError ? "Enter a duration from 1 to 180 minutes" : actionTitle)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Button { input.toggleKind() } label: {
                    Text("\(input.kind == .break ? "Break" : "Timer")  ⇥")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Tab switches between timer and break")
                .accessibilityLabel("\(input.kind == .break ? "Break" : "Timer") mode. Tab to switch")
                Spacer(minLength: 0)
                Text("⌘1 10m   ⌘2 15m   ⌘3 1h")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 36)
        }
        .background(.black.opacity(0.65))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1) }
        .preferredColorScheme(.dark)
        .onExitCommand { controller.dismissLauncher() }
    }

    private func submit() {
        guard let minutes = input.minutes else { input.showsError = true; return }
        controller.start(minutes: minutes, kind: input.kind)
    }
}

private struct FocusTimerPopover: View {
    @ObservedObject var controller: FocusTimerController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(controller.session.kind == .break ? "Break" : "Timer", systemImage: "timer").font(.headline)
                Spacer()
                if controller.session.phase == .paused {
                    Text("Paused").font(.caption).foregroundStyle(.secondary)
                }
            }
            if controller.session.phase == .completed {
                Label("Time’s up", systemImage: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
                Text(controller.session.kind == .break ? "Your break is over." : "Your timer is complete.")
                    .foregroundStyle(.secondary)
                if controller.session.kind == .timer {
                    Button("Log this hour…") { controller.finishHour() }
                }
                Button("Start another hour") { controller.start(minutes: 60) }
                    .buttonStyle(.borderedProminent)
                Button("Done") { controller.reset() }

            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

private struct DetachedFocusTimer: View {
    @ObservedObject var controller: FocusTimerController
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if hovering {
                Button { controller.pauseOrResume() } label: {
                    Label(controller.session.phase == .paused ? "Resume" : "Pause",
                          systemImage: controller.session.phase == .paused ? "play.circle" : "pause.circle")
                }
                .disabled(controller.session.phase == .completed)
                Button { controller.complete() } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
                .disabled(controller.session.phase == .completed)
                .help("Complete timer").accessibilityLabel("Complete timer")
                Menu {
                    Button("Cancel", systemImage: "xmark.circle") { controller.reset() }
                    Button("Attach to menu bar", systemImage: "arrow.up.circle") { controller.attach() }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More timer controls").accessibilityLabel("More timer controls")
                Spacer(minLength: 0)
            } else {
                Text(controller.session.phase == .completed ? "Done" : controller.remainingText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                Text(controller.session.phase == .completed ? "Time’s up" : (controller.session.kind == .break ? "Break" : "Timer"))
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            TimerDragGrip().frame(width: 14, height: 22).help("Drag timer")
        }
        .buttonStyle(DetachedTimerButtonStyle())
        .padding(.horizontal, 8)
        .frame(width: 220, height: 28)
        .background {
            GeometryReader { proxy in
                Color.green.opacity(0.28)
                    .frame(width: proxy.size.width * controller.session.progress(at: controller.now))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1) }
        .preferredColorScheme(.dark)
        .onHover { hovering = $0 }
    }
}

private struct DetachedTimerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.1),
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TimerDragGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> TimerDragGripView { TimerDragGripView() }
    func updateNSView(_ nsView: TimerDragGripView, context: Context) {}
}

private final class TimerDragGripView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel("Drag timer")
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.65).setFill()
        for x in [4.0, 10.0] {
            for offset in [-6.0, 0.0, 6.0] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.5, y: bounds.midY + offset - 1.5, width: 3, height: 3)).fill()
            }
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        if let window {
            UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "focusTimerDetachedOrigin")
        }
    }
}

/// Non-activating, click-through windows preserve the current app and cover all connected displays.
@MainActor
private final class TimerCompletionGlow {
    private var panels: [NSPanel] = []
    private var dismissal: Task<Void, Never>?
    private var clickMonitors: [Any] = []

    func present(persistent: Bool = false, observeExternalClicks: Bool = true, onDismiss: (() -> Void)? = nil) {
        dismiss()
        let bannerScreen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = persistent ? "Break completed" : "Timer completed"
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: TimerGlowView(
                bannerTopInset: screen == bannerScreen ? screen.frame.maxY - screen.visibleFrame.maxY + 12 : nil,
                persistent: persistent
            ))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        if persistent {
            // Observe clicks without swallowing them or taking focus from the user's app.
            let finish: () -> Void = { [weak self] in
                self?.dismiss()
                onDismiss?()
            }
            if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { event in
                finish()
                return event
            }) { clickMonitors.append(monitor) }
            if observeExternalClicks, let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { _ in
                Task { @MainActor in finish() }
            }) { clickMonitors.append(monitor) }
            return
        }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        clickMonitors.forEach { NSEvent.removeMonitor($0) }
        clickMonitors.removeAll()
        dismissal?.cancel()
        dismissal = nil
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}

private struct TimerGlowView: View {
    let bannerTopInset: CGFloat?
    let persistent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.green.opacity(0.8), lineWidth: 18)
                .blur(radius: 20)
        }
        .padding(3)
        .opacity(visible ? 1 : 0)
        .overlay(alignment: .top) {
            if let bannerTopInset {
                TimerCompletionBanner(isBreak: persistent)
                    .padding(.horizontal, 16)
                    .padding(.top, bannerTopInset)
                    .opacity(persistent || visible ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.8)) { visible = true }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: reduceMotion ? 0 : 0.8)) { visible = false }
        }
    }
}

private struct TimerCompletionBanner: View {
    let isBreak: Bool
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.green.opacity(0.85))
            VStack(alignment: .leading, spacing: 4) {
                Text(isBreak ? "Break is over" : "Timer completed")
                    .font(.system(size: 16, weight: .semibold))
                Text(isBreak ? "Click anywhere when you’re ready." : "Time’s up.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: 384)
        .background(.green.opacity(0.06))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
    }
}
