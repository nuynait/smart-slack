import SwiftUI

struct PromptManagerView: View {
    @EnvironmentObject var promptStore: PromptStore
    @EnvironmentObject var keyboardNav: KeyboardNavigationState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var editingPromptId: UUID?
    @State private var highlightedIndex: Int?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Manage Prompts")
                .font(.title2.bold())
                .padding()

            Picker("", selection: $selectedTab) {
                Text("History").tag(0)
                Text("Saved").tag(1)
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
                    description: Text(selectedTab == 0 ? "Prompts you use will appear here" : "Star prompts to save them permanently")
                )
                Spacer()
            } else {
                List {
                    ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                        PromptRowView(
                            prompt: prompt,
                            isGeneratingTags: promptStore.generatingTagsFor.contains(prompt.id),
                            isHighlighted: highlightedIndex == index,
                            onEdit: { editingPromptId = prompt.id },
                            onStar: {
                                if prompt.isStarred {
                                    promptStore.unstarPrompt(id: prompt.id)
                                } else {
                                    promptStore.starPrompt(id: prompt.id)
                                }
                            },
                            onDelete: { promptStore.deletePrompt(id: prompt.id) }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 550, height: 500)
        .sheet(item: $editingPromptId) { promptId in
            if let prompt = promptStore.prompt(byId: promptId) {
                PromptEditorView(prompt: prompt)
            }
        }
        .onAppear {
            DispatchQueue.main.async { isSearchFocused = false }
        }
        .onDisappear {
            keyboardNav.showPromptManager = false
        }
        .onChange(of: keyboardNav.promptTabCycleDirection) { _, direction in
            guard let direction else { return }
            selectedTab = selectedTab == 0 ? 1 : 0
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
                break // Enter does nothing in manager mode
            case .edit:
                if let idx = highlightedIndex, idx < prompts.count {
                    editingPromptId = prompts[idx].id
                }
            case .dismiss:
                dismiss()
            }
            keyboardNav.promptAction = nil
        }
        .onChange(of: keyboardNav.focusPromptSearch) { _, focus in
            if focus {
                isSearchFocused = true
                keyboardNav.focusPromptSearch = false
            }
        }
        .onChange(of: selectedTab) { _, _ in
            highlightedIndex = nil
        }
        .onChange(of: searchText) { _, _ in
            highlightedIndex = nil
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

// MARK: - UUID Identifiable for sheet

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Prompt Row

struct PromptRowView: View {
    let prompt: SavedPrompt
    let isGeneratingTags: Bool
    var isHighlighted: Bool = false
    let onEdit: () -> Void
    let onStar: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt.displayName)
                .font(.headline)
                .lineLimit(1)

            Text(prompt.text)
                .lineLimit(2)
                .font(.callout)
                .foregroundStyle(.secondary)

            if isGeneratingTags {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Generating tags...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if !prompt.tags.isEmpty {
                PromptTagsView(tags: prompt.tags)
            }

            HStack {
                Text(prompt.updatedAt.relativeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    onStar()
                } label: {
                    Image(systemName: prompt.isStarred ? "star.fill" : "star")
                        .foregroundStyle(prompt.isStarred ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(prompt.isStarred ? "Unstar" : "Star")

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete")
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

// MARK: - Tags Display

struct PromptTagsView: View {
    let tags: [PromptTag]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(tags) { tag in
                Text(tag.name)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tagColor(tag).opacity(0.15))
                    .foregroundStyle(tagColor(tag))
                    .clipShape(Capsule())
            }
        }
    }

    private func tagColor(_ tag: PromptTag) -> Color {
        let index = PromptStore.stableColorIndex(for: tag.name)
        return UserColorStore.presetColors[index]
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }

        return (positions, CGSize(width: totalWidth, height: totalHeight))
    }
}
