import SwiftUI

struct ChannelPickerView: View {
    let channels: [SlackChannel]
    @Binding var selectedId: String
    @Binding var selectedName: String

    @State private var search = ""
    @State private var showStarredOnly = false
    @State private var starredIds: Set<String> = []

    private var displayedChannels: [SlackChannel] {
        var result = channels

        if showStarredOnly {
            result = result.filter { starredIds.contains($0.id) }
        }

        if !search.isEmpty {
            result = result.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
        }

        return result.sorted { a, b in
            let aStarred = starredIds.contains(a.id)
            let bStarred = starredIds.contains(b.id)
            if aStarred != bStarred { return aStarred }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search channels...", text: $search)
                    .textFieldStyle(.plain)

                Button {
                    showStarredOnly.toggle()
                } label: {
                    Image(systemName: showStarredOnly ? "star.fill" : "star")
                        .foregroundStyle(showStarredOnly ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(showStarredOnly ? "Show all" : "Show starred only")
            }
            .padding(8)
            .background(.quaternary)
            .cornerRadius(6)

            Divider()

            if displayedChannels.isEmpty {
                VStack(spacing: 8) {
                    Text(showStarredOnly ? "No starred channels" : "No channels found")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayedChannels, selection: $selectedId) { channel in
                    ChannelRow(
                        channel: channel,
                        isSelected: channel.id == selectedId,
                        isStarred: starredIds.contains(channel.id),
                        onToggleStar: { toggleStar(channel.id) }
                    )
                    .tag(channel.id)
                }
                .listStyle(.plain)
                .onChange(of: selectedId) { _, newValue in
                    selectedName = channels.first { $0.id == newValue }?.displayName ?? ""
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .onAppear { loadStarred() }
    }

    private func toggleStar(_ id: String) {
        if starredIds.contains(id) {
            starredIds.remove(id)
        } else {
            starredIds.insert(id)
        }
        saveStarred()
    }

    private func loadStarred() {
        guard let data = try? Data(contentsOf: Constants.starredChannelsFile),
              let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        starredIds = ids
    }

    private func saveStarred() {
        guard let data = try? JSONEncoder().encode(starredIds) else { return }
        try? data.write(to: Constants.starredChannelsFile)
    }
}

private struct ChannelRow: View {
    let channel: SlackChannel
    let isSelected: Bool
    let isStarred: Bool
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: channelIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(channel.displayName)
                .lineLimit(1)

            Spacer()

            Button {
                onToggleStar()
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(isStarred ? .yellow : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var channelIcon: String {
        if channel.isIm == true { return "person" }
        if channel.isMpim == true { return "person.3" }
        if channel.isGroup == true { return "lock" }
        return "number"
    }
}
