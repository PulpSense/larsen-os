import SwiftUI

struct PhrasesView: View {
    @ObservedObject var store: WallStore
    @ObservedObject private var navigation = DashboardNavigation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phrases")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Choose a phrase to read it. Edit its Markdown when you need to make changes.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let phraseID = store.addDesktopPhrase()
                    PhraseDesktopPanelController.shared.present(phraseID: phraseID, store: store)
                    navigation.selectedPhraseID = phraseID
                    navigation.editingPhraseID = phraseID
                } label: {
                    Label("New phrase", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 16) {
                phraseList
                    .frame(width: 210)

                phraseDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .navigationTitle("Phrases")
        .onAppear {
            if navigation.selectedPhraseID == nil {
                navigation.selectedPhraseID = store.desktopPhrases.first?.id
            }
        }
        .onChange(of: navigation.selectedPhraseID) { _, selectedID in
            if navigation.editingPhraseID != selectedID { navigation.editingPhraseID = nil }
        }
        .onDisappear { navigation.editingPhraseID = nil }
    }

    private var phraseDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditing ? "Edit Markdown" : "Phrase preview")
                        .font(.headline)
                    if let selectedPhrase {
                        Text(title(for: selectedPhrase))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(isEditing ? "Done" : "Edit phrase", systemImage: isEditing ? "checkmark" : "pencil") {
                    navigation.editingPhraseID = isEditing ? nil : selectedPhrase?.id
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPhrase == nil)
            }

            HStack {
                Text("Desktop window")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Show on desktop", isOn: Binding(
                    get: { selectedPhrase?.isVisible ?? false },
                    set: { visible in
                        guard let phrase = selectedPhrase else { return }
                        setVisibility(visible, of: phrase)
                    }
                ))
                .toggleStyle(.switch)
                .fixedSize()
                .disabled(selectedPhrase == nil)
            }

            if isEditing {
                TextEditor(text: selectedMarkdownBinding)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView {
                    DesktopPhraseMarkdownView(
                        markdown: selectedPhrase?.markdown ?? "",
                        allowsTextSelection: true
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    private var isEditing: Bool {
        selectedPhrase?.id == navigation.editingPhraseID
    }

    private var phraseList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Phrase windows", systemImage: "rectangle.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            List(selection: $navigation.selectedPhraseID) {
                ForEach(store.desktopPhrases) { phrase in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(for: phrase))
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                                .help(title(for: phrase))
                            Text(phrase.isVisible ? "On desktop" : "Hidden")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Menu {
                            Button(phrase.isVisible ? "Hide from desktop" : "Show on desktop", systemImage: phrase.isVisible ? "eye.slash" : "eye") {
                                toggleVisibility(of: phrase)
                            }
                            if store.desktopPhrases.count > 1 {
                                Divider()
                                Button("Delete phrase", systemImage: "trash", role: .destructive) {
                                    delete(phrase)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 24, height: 24)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .help("Phrase actions")
                    }
                    .tag(phrase.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectedMarkdownBinding: Binding<String> {
        Binding(
            get: { selectedPhrase?.markdown ?? "" },
            set: { markdown in
                guard let selectedPhraseID = navigation.selectedPhraseID else { return }
                store.updateDesktopPhrase(selectedPhraseID, markdown: markdown)
            }
        )
    }

    private var selectedPhrase: DesktopPhrase? {
        guard let selectedPhraseID = navigation.selectedPhraseID else { return nil }
        return store.desktopPhrase(selectedPhraseID)
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
        setVisibility(!phrase.isVisible, of: phrase)
    }

    private func setVisibility(_ visible: Bool, of phrase: DesktopPhrase) {
        if visible {
            PhraseDesktopPanelController.shared.present(phraseID: phrase.id, store: store)
        } else {
            PhraseDesktopPanelController.shared.dismiss(phraseID: phrase.id, store: store)
        }
    }

    private func delete(_ phrase: DesktopPhrase) {
        let remaining = store.desktopPhrases.filter { $0.id != phrase.id }
        PhraseDesktopPanelController.shared.remove(phraseID: phrase.id, store: store)
        if navigation.selectedPhraseID == phrase.id {
            navigation.selectedPhraseID = remaining.first?.id
        }
    }
}
