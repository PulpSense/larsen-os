import AppKit
import SwiftUI

@MainActor
final class PhraseDesktopPanelController {
    static let shared = PhraseDesktopPanelController()

    private let legacyEnabledKey = "desktopPhrasePanelEnabled"
    private var panels: [UUID: DesktopWallPanel] = [:]

    private init() {}

    func restoreIfEnabled(store: WallStore) {
        let defaults = UserDefaults.standard
        let primaryEnabled = defaults.object(forKey: legacyEnabledKey) == nil
            || defaults.bool(forKey: legacyEnabledKey)
        for phrase in store.desktopPhrases where phrase.isVisible {
            if phrase.id == DesktopPhrase.primaryID && !primaryEnabled { continue }
            present(phraseID: phrase.id, store: store, updateVisibility: false)
        }
    }

    func present(store: WallStore) {
        guard let phraseID = store.desktopPhrases.first?.id else { return }
        present(phraseID: phraseID, store: store)
    }

    func createAndPresent(store: WallStore) -> UUID {
        let phraseID = store.addDesktopPhrase()
        present(phraseID: phraseID, store: store)
        return phraseID
    }

    func present(
        phraseID: UUID,
        store: WallStore,
        updateVisibility: Bool = true
    ) {
        guard store.desktopPhrase(phraseID) != nil else { return }
        if phraseID == DesktopPhrase.primaryID {
            UserDefaults.standard.set(true, forKey: legacyEnabledKey)
        }
        if updateVisibility {
            store.setDesktopPhraseVisibility(phraseID, isVisible: true)
        }

        if let panel = panels[phraseID] {
            panel.orderFrontRegardless()
            return
        }

        let index = store.desktopPhrases.firstIndex(where: { $0.id == phraseID }) ?? 0
        let frameAutosaveName = phraseID == DesktopPhrase.primaryID
            ? "DigitalWallPhraseDesktopPanel"
            : "DigitalWallPhraseDesktopPanel-\(phraseID.uuidString)"

        let panel = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 440, height: 280),
            minimumSize: NSSize(width: 240, height: 150),
            frameAutosaveName: frameAutosaveName,
            defaultOffset: NSPoint(
                x: 36 + CGFloat(index % 6) * 34,
                y: 36 + CGFloat(index % 6) * 34
            )
        ) {
            PhraseDesktopPanelContent(
                store: store,
                phraseID: phraseID,
                newPhrase: { [weak self] in
                    _ = self?.createAndPresent(store: store)
                },
                beginEditing: { [weak self] in
                    self?.activateForEditing(phraseID: phraseID)
                },
                close: { [weak self] in
                    self?.dismiss(phraseID: phraseID, store: store)
                }
            )
        }

        panels[phraseID] = panel
        panel.orderFrontRegardless()
    }

    func dismiss(phraseID: UUID, store: WallStore) {
        if phraseID == DesktopPhrase.primaryID {
            UserDefaults.standard.set(false, forKey: legacyEnabledKey)
        }
        store.setDesktopPhraseVisibility(phraseID, isVisible: false)
        panels[phraseID]?.orderOut(nil)
        panels[phraseID] = nil
    }

    func remove(phraseID: UUID, store: WallStore) {
        panels[phraseID]?.orderOut(nil)
        panels[phraseID] = nil
        store.removeDesktopPhrase(phraseID)
    }

    private func activateForEditing(phraseID: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        panels[phraseID]?.makeKeyAndOrderFront(nil)
    }
}

private struct PhraseDesktopPanelContent: View {
    @ObservedObject var store: WallStore
    let phraseID: UUID
    let newPhrase: () -> Void
    let beginEditing: () -> Void
    let close: () -> Void
    @State private var controlsVisible = false
    @State private var isEditing = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DesktopPanelBackground()

            Group {
                if isEditing {
                    TextEditor(text: phrasesBinding)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                        .padding(18)
                } else {
                    ScrollView {
                        DesktopPhraseMarkdownView(markdown: phraseMarkdown)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(18)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            Group {
                if isEditing {
                    Button("Done") {
                        editorFocused = false
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    DesktopPanelControlMenu(isVisible: controlsVisible) {
                        Button("Edit phrase", systemImage: "pencil") {
                            beginEditing()
                            isEditing = true
                            DispatchQueue.main.async {
                                editorFocused = true
                            }
                        }

                        Button("New phrase window", systemImage: "plus", action: newPhrase)

                        Divider()

                        Button("Close", systemImage: "xmark", role: .destructive, action: close)
                    }
                }
            }
            .padding(12)
        }
        .onHover { controlsVisible = $0 }
        .onExitCommand {
            editorFocused = false
            isEditing = false
        }
    }

    private var phrasesBinding: Binding<String> {
        Binding(
            get: { phraseMarkdown },
            set: { store.updateDesktopPhrase(phraseID, markdown: $0) }
        )
    }

    private var phraseMarkdown: String {
        store.desktopPhrase(phraseID)?.markdown ?? ""
    }

}

private struct DesktopPhraseMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(DesktopPhraseMarkdownBlock.parse(markdown)) { block in
                blockView(block)
            }
        }
        .textSelection(.disabled)
    }

    @ViewBuilder
    private func blockView(_ block: DesktopPhraseMarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level):
            Text(inlineMarkdown(block.text))
                .font(headingFont(level: level))
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(inlineMarkdown(block.text))
            }
            .font(.system(.body, design: .rounded))
        case let .numbered(marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).monospacedDigit()
                Text(inlineMarkdown(block.text))
            }
            .font(.system(.body, design: .rounded))
        case .quote:
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.secondary.opacity(0.55))
                    .frame(width: 3)
                Text(inlineMarkdown(block.text)).italic()
            }
            .font(.system(.body, design: .rounded))
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .font(.system(.body, design: .rounded))
        case .spacer:
            Color.clear.frame(height: 4)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        default: .headline
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

private struct DesktopPhraseMarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case bullet
        case numbered(String)
        case quote
        case paragraph
        case spacer
    }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [DesktopPhraseMarkdownBlock] {
        markdown.components(separatedBy: .newlines).enumerated().map { index, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                return DesktopPhraseMarkdownBlock(id: index, kind: .spacer, text: "")
            }

            let headingMarks = line.prefix { $0 == "#" }.count
            if (1...3).contains(headingMarks),
               line.dropFirst(headingMarks).hasPrefix(" ") {
                return DesktopPhraseMarkdownBlock(
                    id: index,
                    kind: .heading(headingMarks),
                    text: String(line.dropFirst(headingMarks + 1))
                )
            }

            if line.hasPrefix("- ") || line.hasPrefix("+ ") || line.hasPrefix("* ") {
                return DesktopPhraseMarkdownBlock(
                    id: index,
                    kind: .bullet,
                    text: String(line.dropFirst(2))
                )
            }

            if let dot = line.firstIndex(of: ".") {
                let digits = line[..<dot]
                let remainder = line[line.index(after: dot)...]
                if !digits.isEmpty,
                   digits.allSatisfy(\.isNumber),
                   remainder.hasPrefix(" ") {
                    return DesktopPhraseMarkdownBlock(
                        id: index,
                        kind: .numbered("\(digits)."),
                        text: String(remainder.dropFirst())
                    )
                }
            }

            if line.hasPrefix("> ") {
                return DesktopPhraseMarkdownBlock(
                    id: index,
                    kind: .quote,
                    text: String(line.dropFirst(2))
                )
            }

            return DesktopPhraseMarkdownBlock(id: index, kind: .paragraph, text: line)
        }
    }
}
