import SwiftUI

struct PhrasesView: View {
    @ObservedObject var store: WallStore
    @State private var selectedPhraseID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Words worth returning to")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Each desktop window has its own Markdown and remembered position.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let phraseID = PhraseDesktopPanelController.shared.createAndPresent(store: store)
                    selectedPhraseID = phraseID
                } label: {
                    Label("New phrase window", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    guard let selectedPhraseID else { return }
                    PhraseDesktopPanelController.shared.present(
                        phraseID: selectedPhraseID,
                        store: store
                    )
                } label: {
                    Label("Show on Desktop", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(selectedPhraseID == nil)
            }

            HSplitView {
                phraseList
                    .frame(minWidth: 185, idealWidth: 210, maxWidth: 250)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Markdown", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: selectedMarkdownBinding)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                }
                .frame(minWidth: 250)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Preview", systemImage: "eye")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(renderedMarkdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(18)
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                }
                .frame(minWidth: 250)
            }
        }
        .padding(28)
        .navigationTitle("Phrases")
        .onAppear {
            if selectedPhraseID == nil {
                selectedPhraseID = store.desktopPhrases.first?.id
            }
        }
    }

    private var phraseList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Phrase windows", systemImage: "rectangle.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            List(selection: $selectedPhraseID) {
                ForEach(store.desktopPhrases) { phrase in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(for: phrase))
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(phrase.isVisible ? "On desktop" : "Hidden")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            toggleVisibility(of: phrase)
                        } label: {
                            Image(systemName: phrase.isVisible ? "eye.fill" : "eye.slash")
                        }
                        .buttonStyle(.plain)
                        .help(phrase.isVisible ? "Hide from desktop" : "Show on desktop")

                        if store.desktopPhrases.count > 1 {
                            Button(role: .destructive) {
                                delete(phrase)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("Delete phrase window")
                        }
                    }
                    .tag(phrase.id)
                }
            }
            .listStyle(.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var selectedMarkdownBinding: Binding<String> {
        Binding(
            get: { selectedPhrase?.markdown ?? "" },
            set: { markdown in
                guard let selectedPhraseID else { return }
                store.updateDesktopPhrase(selectedPhraseID, markdown: markdown)
            }
        )
    }

    private var selectedPhrase: DesktopPhrase? {
        guard let selectedPhraseID else { return nil }
        return store.desktopPhrase(selectedPhraseID)
    }

    private var renderedMarkdown: AttributedString {
        let markdown = selectedPhrase?.markdown ?? ""
        return (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(markdown)
    }

    private func title(for phrase: DesktopPhrase) -> String {
        let firstLine = phrase.markdown
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled phrase"
        let withoutMarkdown = firstLine.drop {
            $0 == "#" || $0 == "-" || $0 == "*" || $0 == " "
        }
        return withoutMarkdown.isEmpty ? "Untitled phrase" : String(withoutMarkdown)
    }

    private func toggleVisibility(of phrase: DesktopPhrase) {
        if phrase.isVisible {
            PhraseDesktopPanelController.shared.dismiss(phraseID: phrase.id, store: store)
        } else {
            PhraseDesktopPanelController.shared.present(phraseID: phrase.id, store: store)
        }
    }

    private func delete(_ phrase: DesktopPhrase) {
        let remaining = store.desktopPhrases.filter { $0.id != phrase.id }
        PhraseDesktopPanelController.shared.remove(phraseID: phrase.id, store: store)
        if selectedPhraseID == phrase.id {
            selectedPhraseID = remaining.first?.id
        }
    }
}
