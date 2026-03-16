import Foundation
import SwiftUI

struct PromptTag: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var colorIndex: Int
}

struct SavedPrompt: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var text: String
    var tags: [PromptTag]
    var isStarred: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID, name: String = "", text: String, tags: [PromptTag] = [], isStarred: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.text = text
        self.tags = tags
        self.isStarred = isStarred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        text = try container.decode(String.self, forKey: .text)
        tags = try container.decodeIfPresent([PromptTag].self, forKey: .tags) ?? []
        isStarred = try container.decode(Bool.self, forKey: .isStarred)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Display label: name if set, otherwise first line of text truncated.
    var displayName: String {
        if !name.isEmpty { return name }
        let firstLine = text.prefix(60).split(separator: "\n").first.map(String.init) ?? String(text.prefix(60))
        return firstLine
    }
}

@MainActor
final class PromptStore: ObservableObject {
    @Published var prompts: [SavedPrompt] = []
    @Published var generatingTagsFor: Set<UUID> = []
    @Published var maxHistoryCount: Int = 10 {
        didSet { saveSettings(); trimHistory() }
    }

    var historyPrompts: [SavedPrompt] {
        prompts.filter { !$0.isStarred }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var savedPrompts: [SavedPrompt] {
        prompts.filter(\.isStarred)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var allTags: [String] {
        Array(Set(prompts.flatMap { $0.tags.map(\.name) })).sorted()
    }

    init() {
        load()
        loadSettings()
    }

    // MARK: - CRUD

    func addPrompt(text: String, name: String = "") -> SavedPrompt {
        let prompt = SavedPrompt(
            id: UUID(),
            name: name,
            text: text
        )
        prompts.append(prompt)
        trimHistory()
        save()
        return prompt
    }

    func updatePrompt(id: UUID, text: String) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[index].text = text
        prompts[index].updatedAt = Date()
        save()
    }

    func updateName(id: UUID, name: String) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[index].name = name
        save()
    }

    func updateTags(id: UUID, tags: [PromptTag]) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[index].tags = tags
        save()
    }

    func starPrompt(id: UUID) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[index].isStarred = true
        save()
    }

    func unstarPrompt(id: UUID) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[index].isStarred = false
        trimHistory()
        save()
    }

    func deletePrompt(id: UUID) {
        prompts.removeAll { $0.id == id }
        save()
    }

    func prompt(byId id: UUID) -> SavedPrompt? {
        prompts.first { $0.id == id }
    }

    // MARK: - Tag Generation

    func generateTags(for promptId: UUID) async {
        guard let prompt = prompt(byId: promptId) else { return }
        generatingTagsFor.insert(promptId)
        let existingTags = allTags

        do {
            let tagNames = try await ClaudeService.generateTags(
                promptText: prompt.text,
                existingTags: existingTags
            )
            let tags = tagNames.map { name in
                PromptTag(
                    id: UUID(),
                    name: name,
                    colorIndex: Self.stableColorIndex(for: name)
                )
            }
            updateTags(id: promptId, tags: tags)
        } catch {
            // Tag generation is best-effort; silently ignore errors
        }
        generatingTagsFor.remove(promptId)
    }

    static func stableColorIndex(for name: String) -> Int {
        let hash = name.lowercased().utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return abs(hash) % UserColorStore.presetColors.count
    }

    // MARK: - Persistence

    private func trimHistory() {
        let history = prompts.filter { !$0.isStarred }
            .sorted { $0.updatedAt > $1.updatedAt }
        if history.count > maxHistoryCount {
            let toRemove = history.suffix(from: maxHistoryCount)
            let removeIds = Set(toRemove.map(\.id))
            prompts.removeAll { removeIds.contains($0.id) }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Constants.promptsFile),
              let decoded = try? JSONDecoder.slackDecoder.decode([SavedPrompt].self, from: data) else { return }
        prompts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.slackEncoder.encode(prompts) else { return }
        try? data.write(to: Constants.promptsFile)
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: Constants.promptSettingsFile),
              let settings = try? JSONDecoder().decode(PromptSettings.self, from: data) else { return }
        maxHistoryCount = settings.maxHistoryCount
    }

    private func saveSettings() {
        let settings = PromptSettings(maxHistoryCount: maxHistoryCount)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: Constants.promptSettingsFile)
    }
}

private struct PromptSettings: Codable {
    var maxHistoryCount: Int
}
