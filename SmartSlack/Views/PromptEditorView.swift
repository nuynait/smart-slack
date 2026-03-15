import SwiftUI

struct PromptEditorView: View {
    let prompt: SavedPrompt
    @EnvironmentObject var promptStore: PromptStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var text: String
    @State private var hasEdited = false

    init(prompt: SavedPrompt) {
        self.prompt = prompt
        _name = State(initialValue: prompt.name)
        _text = State(initialValue: prompt.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Prompt")
                .font(.title2.bold())
                .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.headline)
                        TextField("Optional name for this prompt", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .formCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt")
                            .font(.headline)
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .font(.body)
                            .onChange(of: text) { _, _ in
                                hasEdited = true
                            }
                    }
                    .formCard()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tags")
                                .font(.headline)
                            Spacer()
                            if promptStore.generatingTagsFor.contains(prompt.id) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        let tags = promptStore.prompt(byId: prompt.id)?.tags ?? prompt.tags
                        if tags.isEmpty && !promptStore.generatingTagsFor.contains(prompt.id) {
                            Text("No tags yet. Tags will be generated when you save changes.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else if !tags.isEmpty {
                            PromptTagsView(tags: tags)
                        }
                    }
                    .formCard()
                }
                .padding(16)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    Task { await saveAndTag() }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
    }

    private func saveAndTag() async {
        promptStore.updateName(id: prompt.id, name: name)
        promptStore.updatePrompt(id: prompt.id, text: text)

        if hasEdited {
            Task { await promptStore.generateTags(for: prompt.id) }
        }

        dismiss()
    }
}
