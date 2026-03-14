import SwiftUI

struct ScheduleDetailView: View {
    let schedule: Schedule
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @EnvironmentObject var userColorStore: UserColorStore
    @State private var showEditSheet = false
    @State private var colorPickerUserId: String?

    var body: some View {
        Group {
            if let session = schedule.latestSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        Divider()
                        sessionSection(session)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        Divider()
                    }
                    .padding([.horizontal, .top])
                    Spacer()
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock",
                        description: Text("Waiting for the next scheduled check")
                    )
                    Spacer()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if schedule.status == .active {
                    Button {
                        schedulerEngine.triggerManually(schedule.id)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Trigger now")

                    Button {
                        var updated = schedule
                        updated.status = .completed
                        scheduleStore.updateSchedule(updated)
                        schedulerEngine.stopSchedule(schedule.id)
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .help("Mark as completed")
                }

                if schedule.status == .failed || schedule.status == .completed {
                    Button {
                        var updated = schedule
                        updated.status = .active
                        scheduleStore.updateSchedule(updated)
                        schedulerEngine.startSchedule(updated)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Re-activate schedule")
                }

                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit schedule")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditScheduleView(schedule: schedule)
        }
        .task(id: schedule.id) {
            resolveAllUserNames()
        }
        .onChange(of: schedule.sessions.count) { _, _ in
            resolveAllUserNames()
        }
        .onChange(of: schedule.pendingMessages.count) { _, _ in
            resolveAllUserNames()
        }
    }

    private func resolveAllUserNames() {
        let messages = conversationMessages
        var allUserIds = messages.compactMap(\.user)
        // Also resolve user IDs mentioned in message text (<@USERID>)
        let mentionPattern = /<@(U[A-Z0-9]+)>/
        for msg in messages {
            guard let text = msg.text else { continue }
            for match in text.matches(of: mentionPattern) {
                allUserIds.append(String(match.1))
            }
        }
        appVM.resolveUserNames(ids: allUserIds)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(schedule.name)
                    .font(.title2.bold())

                statusPill
            }

            HStack(spacing: 16) {
                Label(schedule.channelName, systemImage: channelIcon)
                    .font(.subheadline)

                Label("Every \(formatInterval(schedule.intervalSeconds))", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let lastRun = schedule.lastRun {
                    Label("Last run: \(lastRun.relativeFormatted)", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !schedule.prompt.isEmpty {
                Text(schedule.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.quaternary)
                    .cornerRadius(6)
            }
        }
    }

    private var statusPill: some View {
        Text(schedule.status.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.2))
            .foregroundStyle(pillColor)
            .clipShape(Capsule())
    }

    private var pillColor: Color {
        switch schedule.status {
        case .active: return .statusActive
        case .completed: return .statusCompleted
        case .failed: return .statusFailed
        }
    }

    private var channelIcon: String {
        switch schedule.type {
        case .channel: return "number"
        case .thread: return "bubble.left.and.bubble.right"
        case .dm: return "person"
        case .dmgroup: return "person.3"
        }
    }

    // MARK: - Session

    private static let messageTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        f.timeZone = .current
        return f
    }()

    private func slackTsToDate(_ ts: String?) -> Date? {
        guard let ts, let interval = Double(ts.split(separator: ".").first ?? "") else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private var latestMessageIds: Set<String> {
        guard let latest = schedule.latestSession else { return [] }
        return Set(latest.messages.compactMap(\.ts))
    }

    private var conversationMessages: [SlackMessage] {
        // Collect messages from all sessions + pending, deduplicate by ts, sort newest first
        var seen = Set<String>()
        var all: [SlackMessage] = []
        for session in schedule.sessions {
            for msg in session.messages {
                let key = msg.ts ?? UUID().uuidString
                if !seen.contains(key) {
                    seen.insert(key)
                    all.append(msg)
                }
            }
        }
        for msg in schedule.pendingMessages {
            let key = msg.ts ?? UUID().uuidString
            if !seen.contains(key) {
                seen.insert(key)
                all.append(msg)
            }
        }
        return all.sorted { ($0.ts ?? "") > ($1.ts ?? "") }
    }

    private func sessionSection(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            if let summary = session.summary {
                sectionHeader("Summary", icon: "text.alignleft")
                MarkdownView(text: summary)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(8)
            }

            // Draft
            if session.finalAction == .pending {
                DraftView(schedule: schedule, session: session)
            } else {
                completedActionView(session)
            }

            // Draft History
            if !session.draftHistory.isEmpty {
                DraftHistoryView(schedule: schedule, session: session)
            }

            // Conversation (newest on top)
            let messages = conversationMessages
            if !messages.isEmpty {
                sectionHeader("Conversation", icon: "bubble.left.and.bubble.right")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let isLatest = latestMessageIds.contains(message.ts ?? "")
                        let isOwner = message.user == appVM.slackUserId
                        let nextIsLatest = index + 1 < messages.count ? latestMessageIds.contains(messages[index + 1].ts ?? "") : false
                        let isLastNew = isLatest && !nextIsLatest

                        messageRow(message: message, isLatest: isLatest, isOwner: isOwner)

                        if isLastNew {
                            olderDivider
                        }
                    }
                }
                .padding(8)
                .popover(isPresented: Binding(
                    get: { colorPickerUserId != nil },
                    set: { if !$0 { colorPickerUserId = nil } }
                )) {
                    if let userId = colorPickerUserId {
                        userColorPicker(userId: userId)
                    }
                }
            }
        }
    }

    private func completedActionView(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                session.finalAction == .sent ? "Sent" : "Ignored",
                icon: session.finalAction == .sent ? "paperplane.fill" : "xmark.circle"
            )

            if let sent = session.sentMessage {
                Text(sent)
                    .padding(12)
                    .background(.green.opacity(0.1))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
        }
    }

    private func messageRow(message: SlackMessage, isLatest: Bool, isOwner: Bool) -> some View {
        let userId = message.user ?? "?"
        let nameColor: Color = isOwner ? .primary : userColorStore.color(for: userId)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(appVM.displayName(for: userId))
                    .font(.caption.bold())
                    .foregroundStyle(nameColor)
                if isOwner {
                    Text("owner")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 50, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isOwner {
                    colorPickerUserId = userId
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                richMessageText(message.text ?? "")
                    .font(isLatest ? .body : .callout)
                    .foregroundStyle(isOwner ? Color.primary.opacity(0.7) : (isLatest ? Color.primary : Color.secondary))
                    .textSelection(.enabled)

                if !message.imageFiles.isEmpty {
                    messageImages(message.imageFiles)
                }

                if let date = slackTsToDate(message.ts) {
                    Text(Self.messageTimestampFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isOwner
                ? Color.gray.opacity(0.08)
                : nameColor.opacity(0.08)
        )
    }

    private func messageImages(_ files: [SlackFile]) -> some View {
        HStack(spacing: 6) {
            ForEach(files) { file in
                SlackImageView(file: file, slackService: appVM.slackService)
            }
        }
    }

    private func userColorPicker(userId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appVM.displayName(for: userId))
                .font(.headline)
                .padding(.bottom, 2)

            let columns = Array(repeating: GridItem(.fixed(24), spacing: 6), count: 5)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<UserColorStore.presetColors.count, id: \.self) { index in
                    let isSelected = userColorStore.colorIndex(for: userId) == index
                    Circle()
                        .fill(UserColorStore.presetColors[index])
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: isSelected ? 2 : 0)
                        )
                        .shadow(color: isSelected ? .primary.opacity(0.3) : .clear, radius: 2)
                        .contentShape(Circle())
                        .onTapGesture {
                            userColorStore.setColor(for: userId, index: index)
                        }
                }
            }
        }
        .padding(12)
    }

    private var olderDivider: some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(.orange.opacity(0.5))
            Text("Older")
                .font(.caption2.bold())
                .foregroundStyle(.orange)
            Rectangle().frame(height: 1).foregroundStyle(.orange.opacity(0.5))
        }
        .padding(.vertical, 6)
    }

    private func richMessageText(_ raw: String) -> Text {
        let mentionPattern = /<@(U[A-Z0-9]+)>/
        var result = Text("")
        var remaining = raw[...]

        while let match = remaining.firstMatch(of: mentionPattern) {
            let before = remaining[remaining.startIndex..<match.range.lowerBound]
            if !before.isEmpty {
                result = result + Text(before)
            }
            let mentionedId = String(match.1)
            let name = "@\(appVM.displayName(for: mentionedId))"
            let color = mentionedId == appVM.slackUserId ? Color.primary : userColorStore.color(for: mentionedId)
            result = result + Text(name).bold().foregroundColor(color)
            remaining = remaining[match.range.upperBound...]
        }
        if !remaining.isEmpty {
            result = result + Text(remaining)
        }
        return result
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func formatInterval(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        if remaining == 0 { return "\(minutes)m" }
        return "\(minutes)m \(remaining)s"
    }
}
