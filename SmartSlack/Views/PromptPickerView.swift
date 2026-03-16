import SwiftUI

struct PromptPickerView: View {
    @EnvironmentObject var promptStore: PromptStore
    @EnvironmentObject var keyboardNav: KeyboardNavigationState
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    @State private var selectedTab = 1 // Default to saved
    @State private var searchText = ""
    @State private var editingPromptId: UUID?
    @State private var highlightedIndex: Int?
    @FocusState private var isSearchFocused: Bool

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

            TextField("Search prompts... (s)", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
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
                    ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                        PickerRowView(
                            prompt: prompt,
                            isHighlighted: highlightedIndex == index,
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
        .onChange(of: keyboardNav.promptTabCycleDirection) { _, direction in
            guard let direction else { return }
            let tabs = [1, 0] // Saved, History order
            guard let idx = tabs.firstIndex(of: selectedTab) else {
                keyboardNav.promptTabCycleDirection = nil
                return
            }
            switch direction {
            case .left:
                selectedTab = tabs[(idx - 1 + tabs.count) % tabs.count]
            case .right:
                selectedTab = tabs[(idx + 1) % tabs.count]
            }
            highlightedIndex = nil
            keyboardNav.promptTabCycleDirection = nil
        }
        .onChange(of: keyboardNav.promptMoveDirection) { _, direction in
            guard let direction else { return }
            let count = filteredPrompts.count
            guard count > 0 else {
                keyboardNav.promptMoveDirection = nil
                return
            }
            switch direction {
            case .down:
                if let idx = highlightedIndex {
                    highlightedIndex = min(idx + 1, count - 1)
                } else {
                    highlightedIndex = 0
                }
            case .up:
                if let idx = highlightedIndex {
                    highlightedIndex = max(idx - 1, 0)
                } else {
                    highlightedIndex = count - 1
                }
            }
            keyboardNav.promptMoveDirection = nil
        }
        .onChange(of: keyboardNav.promptAction) { _, action in
            guard let action else { return }
            let prompts = filteredPrompts
            switch action {
            case .select:
                if let idx = highlightedIndex, idx < prompts.count {
                    onSelect(prompts[idx].text)
                    dismiss()
                }
            case .edit:
                if let idx = highlightedIndex, idx < prompts.count {
                    editingPromptId = prompts[idx].id
                }
            case .dismiss:
                dismiss()
            }
            keyboardNav.promptAction = nil
        }
        .onChange(of: selectedTab) { _, _ in
            highlightedIndex = nil
        }
        .onChange(of: searchText) { _, _ in
            highlightedIndex = nil
        }
        .onChange(of: keyboardNav.focusPromptSearch) { _, focus in
            if focus {
                isSearchFocused = true
                keyboardNav.focusPromptSearch = false
            }
        }
        .onAppear {
            DispatchQueue.main.async { isSearchFocused = false }
        }
        .onDisappear {
            keyboardNav.showPromptPicker = false
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
    var isHighlighted: Bool = false
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
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}
