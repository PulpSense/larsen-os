import AppKit

enum HourCheckInPresentationSource {
    case app
    case externalURL
}

@MainActor
final class HourCheckInPanelController {
    static let shared = HourCheckInPanelController()
    private var panel: CheckInPanel?
    private var editor: CheckInEditorController?
    private var backdrops: [NSPanel] = []
    private var previousApplication: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private weak var previousKeyWindow: NSWindow?
    private var presentationID = UUID()

    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?

    private init() {
        rememberActiveApplication()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self?.lastExternalApplication = app
                }
            }
        }
    }

    func rememberActiveApplication() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApplication = app
        }
    }

    func toggle(store: WallStore) {
        if panel?.isVisible == true { dismiss() } else { present(store: store) }
    }

    func present(store: WallStore, source: HourCheckInPresentationSource = .app) {
        if panel?.isVisible == true {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        rememberActiveApplication()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let openedAfterURLActivation = source == .externalURL
            && frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        previousApplication = openedAfterURLActivation ? lastExternalApplication : (frontmost ?? lastExternalApplication)
        previousKeyWindow = !openedAfterURLActivation && NSApp.isActive ? NSApp.keyWindow : nil
        presentationID = UUID()
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }
        if editor == nil {
            editor = CheckInEditorController(store: store, dismiss: { [weak self] in self?.dismiss() },
                celebrate: { [weak self] hours in
                    guard let self else { return }
                    let restore = self.dismiss(restoringFocus: false)
                    DeepWorkCelebrationPresenter.shared.present(hours: hours,
                        streak: ConsistencyStreak.current(completedDays: store.completedDays, through: Date(),
                                                          calendar: TrackerCalendar.calendar),
                        hideApplicationOnDismiss: false, onDismiss: restore)
                })
        }
        guard let editor else { return }
        let size = NSSize(width: min(680, screen.visibleFrame.width - 40),
                          height: min(780, screen.visibleFrame.height - 40))
        let frame = NSRect(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
        let panel = CheckInPanel(contentRect: frame, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.title = "Finish hour"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.contentViewController = editor
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setFrame(frame, display: true)
        panel.autorecalculatesKeyViewLoop = false
        panel.dismissForm = { [weak self] in self?.dismiss() }
        panel.submitForm = { [weak editor] in editor?.submit() }
        panel.moveFocus = { [weak editor] backwards in editor?.moveFocus(backwards: backwards) }
        self.panel = panel
        showBackdrops()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }
        // Borrow keyboard focus without activating the app or switching the user’s Space.
        panel.makeKeyAndOrderFront(nil)
        editor.focusActivity()
    }

    private func showBackdrops() {
        for screen in NSScreen.screens {
            let backdrop = CheckInBackdropPanel(contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            backdrop.backgroundColor = NSColor.black.withAlphaComponent(0.28)
            backdrop.isOpaque = false
            backdrop.hasShadow = false
            backdrop.hidesOnDeactivate = false
            backdrop.dismissForm = { [weak self] in self?.dismiss() }
            backdrop.orderFrontRegardless()
            backdrops.append(backdrop)
        }
    }

    @discardableResult
    func dismiss(restoringFocus: Bool = true) -> (() -> Void)? {
        guard let panel else { return nil }
        let appToRestore = previousApplication
        let windowToRestore = previousKeyWindow
        let dismissedPresentation = presentationID
        // Closing releases the panel’s keyboard ownership; hiding alone is insufficient.
        panel.close()
        panel.contentViewController = nil
        self.panel = nil
        backdrops.forEach { $0.close() }
        backdrops.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        previousApplication = nil
        previousKeyWindow = nil

        // Wait until Escape’s event dispatch has unwound before handing activation back.
        let restore: () -> Void = { [weak self] in
            guard let self, self.panel == nil, self.presentationID == dismissedPresentation,
                  let appToRestore, !appToRestore.isTerminated else { return }
            if appToRestore.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                windowToRestore?.makeKeyAndOrderFront(nil)
            } else if NSWorkspace.shared.frontmostApplication?.processIdentifier != appToRestore.processIdentifier {
                NSApp.yieldActivation(to: appToRestore)
                appToRestore.activate(from: .current, options: [])
            }
        }
        if restoringFocus { DispatchQueue.main.async { restore() } }
        return restore
    }
}

private final class CheckInBackdropPanel: NSPanel {
    var dismissForm: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func mouseDown(with event: NSEvent) { dismissForm?() }
}

private final class CheckInPanel: NSPanel {
    var dismissForm: (() -> Void)?
    var submitForm: (() -> Void)?
    var moveFocus: ((Bool) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { dismissForm?(); return }
            if event.keyCode == 48 {
                moveFocus?(event.modifierFlags.contains(.shift))
                return
            }
            if event.modifierFlags.contains(.command), event.keyCode == 36 || event.keyCode == 76 {
                submitForm?()
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class CheckInEditorController: NSViewController {
    private let store: WallStore
    private let dismiss: () -> Void
    private let celebrate: (Int) -> Void
    private var submissionID = UUID()
    private let category = NSPopUpButton()
    private let deepWork = NSSwitch()
    private let activity = NSTextView()
    private let distractions = NSTextView()
    private var preparation: [NSButton] = []
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let submitButton = NSButton(title: "Save this hour", target: nil, action: nil)
    private var focusOrder: [NSView] = []
    private let dateLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let progress = CheckInProgressView()
    private let preparationStack = NSStackView()
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)

    init(store: WallStore, dismiss: @escaping () -> Void, celebrate: @escaping (Int) -> Void) {
        self.store = store
        self.dismiss = dismiss
        self.celebrate = celebrate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let background = CheckInBackgroundView(frame: NSRect(x: 0, y: 0, width: 680, height: 780))
        background.appearance = NSAppearance(named: .darkAqua)
        view = background
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: background.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        let document = CheckInDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 8
        let eyebrow = label("An hour well spent", font: .systemFont(ofSize: 12, weight: .medium))
        eyebrow.textColor = CheckInPalette.gold
        header.addArrangedSubview(eyebrow)
        header.addArrangedSubview(label("Nice work. Capture the hour.", font: .systemFont(ofSize: 28, weight: .semibold)))
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = CheckInPalette.muted
        header.addArrangedSubview(dateLabel)
        stack.addArrangedSubview(header)

        let progressStack = NSStackView()
        progressStack.orientation = .vertical
        progressStack.alignment = .leading
        progressStack.spacing = 9
        progressLabel.font = .systemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = CheckInPalette.gold
        progressStack.addArrangedSubview(progressLabel)
        progressStack.addArrangedSubview(progress)
        stack.addArrangedSubview(progressStack)
        progressStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        progress.widthAnchor.constraint(equalTo: progressStack.widthAnchor).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 5).isActive = true

        addAnswer("What did you accomplish?", text: activity, height: 92, to: stack)
        addAnswer("What pulled your attention away?", text: distractions, height: 56, to: stack)
        let hint = label("No distractions? Write ‘None’.", font: .systemFont(ofSize: 11))
        hint.textColor = CheckInPalette.muted
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(9, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])

        category.addItems(withTitles: ["Choose a category"] + HourCategory.allCases.map(\.rawValue))
        category.setAccessibilityLabel("Category")
        category.font = .systemFont(ofSize: 13)
        let metadata = NSStackView(views: [label("Category", font: .systemFont(ofSize: 12, weight: .medium)), category])
        metadata.spacing = 14
        stack.addArrangedSubview(metadata)
        deepWork.setAccessibilityLabel("Deep work hour")
        deepWork.target = self
        deepWork.action = #selector(updateButtonTitle)
        let deepWorkRow = NSStackView(views: [deepWork, label("Deep work hour", font: .systemFont(ofSize: 14, weight: .medium))])
        deepWorkRow.spacing = 12
        stack.addArrangedSubview(deepWorkRow)

        let preparationHeading = label("Daily preparation", font: .systemFont(ofSize: 12, weight: .medium))
        preparationHeading.textColor = CheckInPalette.muted
        stack.addArrangedSubview(preparationHeading)
        stack.setCustomSpacing(10, after: preparationHeading)
        preparationStack.orientation = .vertical
        preparationStack.alignment = .leading
        preparationStack.spacing = 10
        for title in ["I read the 10X Rule.", "I reviewed my Top Goals.",
                      "I reviewed the 3.0 Version of Myself.", "I read my Motivation List out loud.",
                      "I read my Thought Habits.", "I reviewed my vision board."] {
            let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            checkbox.font = .systemFont(ofSize: 12)
            preparation.append(checkbox)
        }
        for index in stride(from: 0, to: preparation.count, by: 2) {
            let row = NSStackView(views: [preparation[index], preparation[index + 1]])
            row.distribution = .fillEqually
            row.spacing = 18
            preparationStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: preparationStack.widthAnchor).isActive = true
        }
        stack.addArrangedSubview(preparationStack)
        preparationStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)

        clearButton.target = self
        clearButton.action = #selector(clearForm)
        clearButton.isBordered = false
        clearButton.contentTintColor = CheckInPalette.muted
        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.bezelStyle = .rounded
        submitButton.controlSize = .large
        submitButton.font = .systemFont(ofSize: 14, weight: .semibold)
        submitButton.bezelColor = CheckInPalette.gold
        submitButton.contentTintColor = CheckInPalette.background
        submitButton.keyEquivalent = "\r"
        submitButton.keyEquivalentModifierMask = [.command]
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let footer = NSStackView(views: [clearButton, spacer, submitButton])
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        submitButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 185).isActive = true
        let keyboard = label("Tab to move   ·   ⌘Return to save   ·   Esc to return to your work", font: .systemFont(ofSize: 11))
        keyboard.textColor = CheckInPalette.muted
        stack.addArrangedSubview(keyboard)
        updateFocusOrder()
        updateButtonTitle()
    }

    private func addAnswer(_ title: String, text: NSTextView, height: CGFloat, to stack: NSStackView) {
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 9
        group.addArrangedSubview(label(title, font: .systemFont(ofSize: 14, weight: .medium)))
        let area = textArea(text, title: title, height: height)
        group.addArrangedSubview(area)
        stack.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        area.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
    }

    private func updateFocusOrder() {
        // Follow the visible rows: left checkbox, right checkbox, then the next row.
        focusOrder = [activity, distractions, category, deepWork] + preparation + [submitButton, clearButton]
    }

    private func label(_ text: String, font: NSFont = .systemFont(ofSize: 13)) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = CheckInPalette.text
        return label
    }

    private func textArea(_ text: NSTextView, title: String, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 12
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        scroll.layer?.masksToBounds = true
        scroll.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        scroll.hasVerticalScroller = true
        scroll.documentView = text
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        text.font = .systemFont(ofSize: 14)
        text.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        text.textColor = CheckInPalette.text
        text.insertionPointColor = CheckInPalette.gold
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel(title)
        return scroll
    }

    func focusActivity() {
        dateLabel.stringValue = Date().formatted(.dateTime.weekday(.wide).month(.wide).day()) + " · Saved locally, even offline"
        let hours = store.deepWorkHours(on: Date())
        progress.hours = hours
        progressLabel.stringValue = hours >= 4 ? "\(hours) deep work hours today · Day won" :
            "\(hours) of 4 deep work hours today · \(4 - hours) to win the day"
        view.window?.makeFirstResponder(activity)
        activity.scrollToVisible(activity.bounds)
    }

    func moveFocus(backwards: Bool) {
        guard let window = view.window else { return }
        let current = window.firstResponder
        let index = focusOrder.firstIndex { control in
            current === control || (control as? NSControl)?.currentEditor() === current
        } ?? (backwards ? 0 : -1)
        let next = (index + (backwards ? -1 : 1) + focusOrder.count) % focusOrder.count
        window.makeFirstResponder(focusOrder[next])
        focusOrder[next].scrollToVisible(focusOrder[next].bounds)
    }

    @objc private func updateButtonTitle() {
        let title = deepWork.state == .on ? "Save + 1 deep work hour" : "Save this hour"
        submitButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: CheckInPalette.background,
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
        ])
    }

    @objc private func clearForm() {
        submissionID = UUID()
        activity.string = ""
        distractions.string = ""
        category.selectItem(at: 0)
        deepWork.state = .off
        preparation.forEach { $0.state = .off }
        errorLabel.isHidden = true
        updateButtonTitle()
        focusActivity()
    }

    @objc func submit() {
        view.window?.makeFirstResponder(nil)
        let form = HourCheckInForm(
            date: Date(), category: HourCategory(rawValue: category.titleOfSelectedItem ?? ""),
            isDeepWork: deepWork.state == .on, activity: activity.string, distractions: distractions.string,
            preparation: DailyPreparation(
                read10XRule: preparation[0].state == .on, reviewedTopGoals: preparation[1].state == .on,
                reviewedVersionOfMyself: preparation[2].state == .on,
                readMotivationListOutLoud: preparation[3].state == .on,
                readThoughtHabits: preparation[4].state == .on, reviewedVisionBoard: preparation[5].state == .on
            )
        )
        if let message = form.validationMessage {
            showError(message)
            let target: NSView = form.category == nil ? category :
                (form.activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? activity : distractions)
            view.window?.makeFirstResponder(target)
            return
        }
        guard store.finishHour(id: submissionID, form: form) else {
            showError(store.lastError ?? "Couldn’t save your check-in.")
            focusActivity()
            return
        }
        let hours = store.deepWorkHours(on: form.date)
        clearForm()
        if form.isDeepWork, DeepWorkCelebrationMilestone.forHours(hours) != nil {
            celebrate(hours)
        } else {
            dismiss()
            HourCapturedToastPresenter.shared.present(hours: hours, isDeepWork: form.isDeepWork)
        }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }
}

private final class CheckInDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private enum CheckInPalette {
    static let background = NSColor(calibratedRed: 0.075, green: 0.08, blue: 0.095, alpha: 1)
    static let text = NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.88, alpha: 1)
    static let muted = NSColor(calibratedWhite: 0.58, alpha: 1)
    static let gold = NSColor(calibratedRed: 0.96, green: 0.73, blue: 0.43, alpha: 1)
}

private final class CheckInBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.115, blue: 0.105, alpha: 1),
                   ending: CheckInPalette.background)?.draw(in: bounds, angle: 270)
    }
}

private final class CheckInProgressView: NSView {
    var hours = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let width = (bounds.width - 18) / 4
        for index in 0..<4 {
            (index < hours ? CheckInPalette.gold : NSColor.white.withAlphaComponent(0.10)).setFill()
            NSBezierPath(roundedRect: NSRect(x: CGFloat(index) * (width + 6), y: 0, width: width, height: 5),
                         xRadius: 2.5, yRadius: 2.5).fill()
        }
    }
}

@MainActor
private final class HourCapturedToastPresenter {
    static let shared = HourCapturedToastPresenter()
    private var panel: CheckInBackdropPanel?
    private var dismissal: Task<Void, Never>?
    func present(hours: Int, isDeepWork: Bool) {
        dismissal?.cancel()
        panel?.close()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let frame = NSRect(x: screen.visibleFrame.midX - 230, y: screen.visibleFrame.midY - 34, width: 460, height: 68)
        let panel = CheckInBackdropPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let background = CheckInBackgroundView(frame: NSRect(origin: .zero, size: frame.size))
        let label = NSTextField(labelWithString: isDeepWork ? "✓  Hour captured · \(hours) deep work hours today" : "✓  Hour captured. Nice work.")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = CheckInPalette.gold
        label.alignment = .center
        label.frame = NSRect(x: 12, y: 24, width: 436, height: 22)
        background.addSubview(label)
        panel.contentView = background
        panel.orderFrontRegardless()
        self.panel = panel
        dismissal = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            panel?.close()
            self?.panel = nil
        }
    }
}
