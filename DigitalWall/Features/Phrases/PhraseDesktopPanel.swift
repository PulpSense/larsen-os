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

struct DesktopPhraseMarkdownView: View {
    let markdown: String
    var allowsTextSelection = false

    var body: some View {
        if allowsTextSelection {
            blocks.textSelection(.enabled)
        } else {
            blocks.textSelection(.disabled)
        }
    }

    private var blocks: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(DesktopPhraseMarkdownBlock.parse(markdown)) { block in
                blockView(block)
            }
        }
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
        case let .table(table):
            tableView(table)
        case .spacer:
            Color.clear.frame(height: 4)
        }
    }

    private func tableView(_ table: PhraseMarkdownTable) -> some View {
        PhraseTableGridLayout(columnCount: table.headers.count) {
            ForEach(tableCells(for: table)) { cell in
                Text(inlineMarkdown(cell.text))
                    .font(.system(.callout, design: .rounded).weight(cell.isHeader ? .semibold : .regular))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: alignment(for: cell.alignment)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(cell.isHeader ? Color.primary.opacity(0.09) : Color.primary.opacity(0.035))
                    .overlay {
                        Rectangle().stroke(.primary.opacity(0.13), lineWidth: 0.5)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func tableCells(for table: PhraseMarkdownTable) -> [PhraseTableCell] {
        ([table.headers] + table.rows).enumerated().flatMap { rowIndex, row in
            row.enumerated().map { columnIndex, text in
                PhraseTableCell(
                    id: "\(rowIndex)-\(columnIndex)",
                    text: text,
                    alignment: table.alignments[columnIndex],
                    isHeader: rowIndex == 0
                )
            }
        }
    }

    private func alignment(for alignment: PhraseTableAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
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

private struct PhraseTableCell: Identifiable {
    let id: String
    let text: String
    let alignment: PhraseTableAlignment
    let isHeader: Bool
}

private struct PhraseTableGridLayout: Layout {
    let columnCount: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard columnCount > 0, !subviews.isEmpty else { return .zero }
        let width = resolvedWidth(proposal: proposal, subviews: subviews)
        let columnWidth = PhraseTableSizing.columnWidth(
            availableWidth: width,
            columnCount: columnCount
        )
        return CGSize(
            width: width,
            height: rowHeights(subviews: subviews, columnWidth: columnWidth).reduce(0, +)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard columnCount > 0 else { return }
        let columnWidth = PhraseTableSizing.columnWidth(
            availableWidth: bounds.width,
            columnCount: columnCount
        )
        let heights = rowHeights(subviews: subviews, columnWidth: columnWidth)
        var y = bounds.minY

        for (index, subview) in subviews.enumerated() {
            let row = index / columnCount
            let column = index % columnCount
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(column) * columnWidth,
                    y: y
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: heights[row])
            )
            if column == columnCount - 1 || index == subviews.count - 1 {
                y += heights[row]
            }
        }
    }

    private func resolvedWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return max(0, width)
        }

        var columnWidths = Array(repeating: CGFloat.zero, count: columnCount)
        for (index, subview) in subviews.enumerated() {
            let column = index % columnCount
            columnWidths[column] = max(
                columnWidths[column],
                subview.sizeThatFits(.unspecified).width
            )
        }
        return columnWidths.reduce(0, +)
    }

    private func rowHeights(subviews: Subviews, columnWidth: CGFloat) -> [CGFloat] {
        let rowCount = Int(ceil(Double(subviews.count) / Double(columnCount)))
        var heights = Array(repeating: CGFloat.zero, count: rowCount)
        for (index, subview) in subviews.enumerated() {
            let row = index / columnCount
            heights[row] = max(
                heights[row],
                subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            )
        }
        return heights
    }
}
