import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var search = ""
    @State private var currentPage = 0
    private let pageSize = 20

    private var allEntries: [HistoryEntry] {
        scheduleStore.schedules.flatMap { schedule in
            schedule.sessions
                .filter { $0.finalAction != .pending && $0.finalAction != .skipped }
                .map { HistoryEntry(schedule: schedule, session: $0) }
        }
        .sorted { $0.session.timestamp > $1.session.timestamp }
    }

    private var filteredEntries: [HistoryEntry] {
        guard !search.isEmpty else { return allEntries }
        let query = search.lowercased()
        return allEntries.filter { entry in
            entry.schedule.name.lowercased().contains(query)
            || entry.schedule.channelName.lowercased().contains(query)
            || (entry.session.summary?.lowercased().contains(query) == true)
            || (entry.session.draftReply?.lowercased().contains(query) == true)
            || (entry.session.sentMessage?.lowercased().contains(query) == true)
            || entry.session.draftHistory.contains { $0.draft.lowercased().contains(query) }
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(filteredEntries.count) / Double(pageSize))))
    }

    private var pagedEntries: [HistoryEntry] {
        let start = currentPage * pageSize
        guard start < filteredEntries.count else { return [] }
        let end = min(start + pageSize, filteredEntries.count)
        return Array(filteredEntries[start..<end])
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history...", text: $search)
                    .textFieldStyle(.plain)
                    .onChange(of: search) { _, _ in currentPage = 0 }

                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary)

            Divider()

            if pagedEntries.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No History" : "No Results",
                    systemImage: search.isEmpty ? "clock" : "magnifyingglass",
                    description: Text(search.isEmpty ? "Completed sessions will appear here" : "No history matching \"\(search)\"")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(pagedEntries) { entry in
                            HistoryEntryRow(entry: entry)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Pagination
            HStack {
                Text("\(filteredEntries.count) session\(filteredEntries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    currentPage = max(0, currentPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentPage == 0)
                .buttonStyle(.plain)

                Text("Page \(currentPage + 1) of \(totalPages)")
                    .font(.caption)
                    .frame(minWidth: 100)

                Button {
                    currentPage = min(totalPages - 1, currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentPage >= totalPages - 1)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Data

struct HistoryEntry: Identifiable {
    let schedule: Schedule
    let session: Session
    var id: UUID { session.sessionId }
}

// MARK: - Row

private struct HistoryEntryRow: View {
    let entry: HistoryEntry

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        f.timeZone = .current
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label(entry.schedule.name, systemImage: channelIcon)
                    .font(.headline)

                Text(entry.schedule.channelName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                actionBadge

                Text(Self.timestampFormatter.string(from: entry.session.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Summary
            if let summary = entry.session.summary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summary")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            // Memory report
            if let memoryReport = entry.session.memoryReport {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory Updated")
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                    Text(memoryReport)
                        .font(.callout)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.purple.opacity(0.05))
                        .cornerRadius(6)
                }
            }

            // Final draft / sent message
            if entry.session.finalAction == .sent, let sent = entry.session.sentMessage {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sent")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text(sent)
                        .font(.callout)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.green.opacity(0.05))
                        .cornerRadius(6)
                }
            } else if entry.session.finalAction == .ignored, let draft = entry.session.draftReply {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignored Draft")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(draft)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.05))
                        .cornerRadius(6)
                }
            } else if entry.session.finalAction == .skipped {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skipped")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if let reason = entry.session.skipReason {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5))
                            .cornerRadius(6)
                    }
                }
            }

            // Draft history (rewrites)
            if !entry.session.draftHistory.isEmpty {
                DisclosureGroup("Draft History (\(entry.session.draftHistory.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entry.session.draftHistory.reversed()) { draft in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(Self.timestampFormatter.string(from: draft.timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let prompt = draft.rewritePrompt {
                                        Text("Rewrite: \(prompt)")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Text(draft.draft)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5))
                            .cornerRadius(4)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.background)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private var actionBadge: some View {
        let label: String
        let color: Color
        switch entry.session.finalAction {
        case .sent:
            label = "Sent"
            color = .green
        case .ignored:
            label = "Ignored"
            color = .orange
        case .skipped:
            label = "Skipped"
            color = .secondary
        case .pending:
            label = "Pending"
            color = .blue
        }
        return Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var channelIcon: String {
        switch entry.schedule.type {
        case .channel: return "number"
        case .thread: return "bubble.left.and.bubble.right"
        case .dm: return "person"
        case .dmgroup: return "person.3"
        }
    }
}
