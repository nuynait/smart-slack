import SwiftUI

struct PromptPickerView: View {
    @EnvironmentObject var promptStore: PromptStore
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    @State private var selectedTab = 1 // Default to saved
    @State private var searchText = ""
    @State private var editingPromptId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose Prompt")
                    .font(.title3.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Picker("", selection: $selectedTab) {
                Text("Saved").tag(1)
                Text("History").tag(0)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            TextField("Search prompts...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            let prompts = filteredPrompts
            if prompts.isEmpty {
                Spacer()
                ContentUnavailableView(
                    selectedTab == 0 ? "No History" : "No Saved Prompts",
                    systemImage: selectedTab == 0 ? "clock" : "star",
                    description: Text("No prompts to choose from")
                )
                Spacer()
            } else {
                List {
                    ForEach(prompts) { prompt in
                        PickerRowView(
                            prompt: prompt,
                            onSelect: {
                                onSelect(prompt.text)
                                dismiss()
                            },
                            onEdit: {
                                editingPromptId = prompt.id
                            },
                            onStar: {
                                if prompt.isStarred {
                                    promptStore.unstarPrompt(id: prompt.id)
                                } else {
                                    promptStore.starPrompt(id: prompt.id)
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 550, height: 450)
        .sheet(item: $editingPromptId) { promptId in
            if let prompt = promptStore.prompt(byId: promptId) {
                PromptEditorView(prompt: prompt)
            }
        }
    }

    private var filteredPrompts: [SavedPrompt] {
        let base = selectedTab == 0 ? promptStore.historyPrompts : promptStore.savedPrompts
        guard !searchText.isEmpty else { return base }
        let query = searchText.lowercased()
        return base.filter {
            $0.text.lowercased().contains(query) ||
            $0.tags.contains { $0.name.lowercased().contains(query) }
        }
    }
}

// MARK: - Picker Row

private struct PickerRowView: View {
    let prompt: SavedPrompt
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onStar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text(prompt.text)
                    .lineLimit(2)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !prompt.tags.isEmpty {
                    PromptTagsView(tags: prompt.tags)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }

            VStack(spacing: 6) {
                Button {
                    onStar()
                } label: {
                    Image(systemName: prompt.isStarred ? "star.fill" : "star")
                        .foregroundStyle(prompt.isStarred ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
