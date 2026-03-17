import SwiftUI

struct ScheduleDetailView: View {
    let schedule: Schedule
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @EnvironmentObject var userColorStore: UserColorStore
    @EnvironmentObject var promptStore: PromptStore
    @EnvironmentObject var keyboardNav: KeyboardNavigationState
    @State private var showEditSheet = false
    @State private var showPromptPicker = false
    @State private var showDeleteConfirm = false
    @State private var showActiveReply = false
    @State private var showEditSend = false
    @State private var showRewrite = false
    @State private var triggerGenerateDraft = false
    @State private var colorPickerUserId: String?
    @State private var monitorThreadLink: String?
    @State private var showSendTarget = false
    @State private var sendTargetDraft = ""
    @State private var showImagePreview = false
    @State private var imagePreviewIndex = 0
    @State private var conversationPage = 0
    @AppStorage("conversationPageSize") private var pageSize = 20

    var body: some View {
        contentView
            .toolbar { toolbarContent }
            .sheet(isPresented: $showEditSheet) {
                EditScheduleView(schedule: schedule)
            }
            .sheet(isPresented: $showPromptPicker) {
                PromptPickerView { selectedText in
                    var updated = schedule
                    updated.prompt = selectedText
                    updated.filterSummary = nil
                    updated.memorySummary = nil
                    scheduleStore.updateSchedule(updated)
                    appVM.analyzePromptFilter(scheduleId: schedule.id, prompt: selectedText)
                    appVM.analyzePromptMemory(scheduleId: schedule.id, prompt: selectedText)
                }
                .environmentObject(promptStore)
            }
            .sheet(isPresented: Binding(
                get: { monitorThreadLink != nil },
                set: { if !$0 { monitorThreadLink = nil } }
            )) {
                AddScheduleFromLinkView(initialLink: monitorThreadLink ?? "", initialAsThread: true)
            }
            .task(id: schedule.id) {
                conversationPage = 0
                resolveAllUserNames()
            }
            .onChange(of: schedule.sessions.count) { _, _ in resolveAllUserNames() }
            .onChange(of: schedule.pendingMessages.count) { _, _ in resolveAllUserNames() }
            .modifier(KeyboardNavModifier(
                schedule: schedule,
                showEditSheet: $showEditSheet,
                showDeleteConfirm: $showDeleteConfirm,
                showActiveReply: $showActiveReply,
                showEditSend: $showEditSend,
                showRewrite: $showRewrite,
                triggerGenerateDraft: $triggerGenerateDraft,
                scheduleStore: scheduleStore,
                schedulerEngine: schedulerEngine,
                keyboardNav: keyboardNav
            ))
            .overlay {
                if showActiveReply {
                    ActiveReplyView(schedule: schedule, isPresented: $showActiveReply)
                }
                if showEditSend, let session = schedule.latestSession {
                    EditSendOverlay(schedule: schedule, session: session, isPresented: $showEditSend, showSendTarget: $showSendTarget, sendTargetDraft: $sendTargetDraft)
                }
                if showRewrite, let session = schedule.latestSession {
                    RewriteOverlay(schedule: schedule, session: session, isPresented: $showRewrite)
                }
                if showSendTarget {
                    SendTargetOverlay(schedule: schedule, draftText: sendTargetDraft, isPresented: $showSendTarget)
                }
                if showImagePreview {
                    ImagePreviewOverlay(images: buildConversationMessages().flatMap(\.imageFiles), slackService: appVM.slackService, selectedIndex: $imagePreviewIndex, isPresented: $showImagePreview)
                }
            }
    }

    private var contentView: some View {
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                openScheduleHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("View history")

            Button {
                showEditSheet = true
            } label: {
                Image(systemName: "pencil")
            }
            .help("Edit schedule (⌘E)")
        }
    }

    private func openScheduleHistory() {
        let historyView = HistoryView(schedule: schedule)
            .environmentObject(scheduleStore)
        let controller = NSHostingController(rootView: historyView)
        let window = NSWindow(contentViewController: controller)
        window.title = "History — \(schedule.name)"
        window.setContentSize(NSSize(width: 750, height: 550))
        window.makeKeyAndOrderFront(nil)
    }

    private func resolveAllUserNames() {
        let messages = buildConversationMessages()
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

                if schedule.autoSend {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text("Auto Send")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 16) {
                Label(schedule.channelName, systemImage: channelIcon)
                    .font(.subheadline)

                Label(schedule.intervalSeconds == 0 ? "Manual" : "Every \(formatInterval(schedule.intervalSeconds))", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label("Initial: \(schedule.initialMessageCount)", systemImage: "number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(notificationModeLabel, systemImage: notificationModeIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label("Created: \(schedule.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let lastRun = schedule.lastRun {
                    Label("Last run: \(lastRun.relativeFormatted)", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !schedule.prompt.isEmpty {
                HStack(alignment: .top) {
                    Text(schedule.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showPromptPicker = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                            KeyboardHintView(key: "p")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Change prompt")
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(6)
            }

            if appVM.analyzingFilterScheduleIds.contains(schedule.id) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing prompt for filters...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(4)
            } else if let filter = schedule.filterSummary {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 16, alignment: .center)
                    Text("Filter: \(filter)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08))
                .cornerRadius(4)
            }

            if appVM.analyzingMemoryScheduleIds.contains(schedule.id) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing prompt for memory...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(4)
            } else if let memorySummary = schedule.memorySummary {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)
                        .frame(width: 16, alignment: .center)
                    Text("Memory: \(memorySummary)")
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.08))
                .cornerRadius(4)
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

    private var notificationModeLabel: String {
        switch schedule.notificationMode {
        case .macosNotification: return "Notification"
        case .forcePopup: return "Force Popup"
        case .quiet: return "Quiet"
        }
    }

    private var notificationModeIcon: String {
        switch schedule.notificationMode {
        case .macosNotification: return "bell"
        case .forcePopup: return "bell.badge"
        case .quiet: return "bell.slash"
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

    private func buildConversationMessages() -> [SlackMessage] {
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

    private func buildLatestMessageIds() -> Set<String> {
        guard let latest = schedule.latestSession else { return [] }
        return Set(latest.messages.compactMap(\.ts))
    }

    private func buildImageIndexMap(from messages: [SlackMessage]) -> [String: Int] {
        var map: [String: Int] = [:]
        var index = 0
        for msg in messages {
            for file in msg.imageFiles {
                map[file.id] = index
                index += 1
            }
        }
        return map
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

            // Memory Report
            if let memoryReport = session.memoryReport {
                sectionHeader("Memory Updated", icon: "brain")
                MarkdownView(text: memoryReport)
                    .padding(12)
                    .background(.purple.opacity(0.05))
                    .cornerRadius(8)
            }

            // Skipped ticks indicator
            if schedulerEngine.skippedTicks.contains(schedule.id) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundStyle(.teal)
                    Text("New messages waiting — resolve draft to process")
                        .font(.caption.bold())
                        .foregroundStyle(.teal)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.teal.opacity(0.08))
                .cornerRadius(6)
            }

            // Background processing indicator
            if let bgTask = schedulerEngine.backgroundTasks[schedule.id] {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(bgTask.type.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(.purple)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.08))
                .cornerRadius(8)
            }

            // Auto-send toggle
            autoSendToggle

            // Draft
            if session.finalAction == .pending || session.finalAction == .skipped {
                DraftView(schedule: schedule, session: session, showEditSend: $showEditSend, showRewrite: $showRewrite, showSendTarget: $showSendTarget, sendTargetDraft: $sendTargetDraft, triggerGenerateDraft: $triggerGenerateDraft)
            } else {
                completedActionView(session)
            }

            // Active Reply
            Button {
                showActiveReply = true
            } label: {
                HStack(spacing: 4) {
                    Label("Active Reply", systemImage: "arrow.uturn.left.circle")
                    KeyboardHintView(key: "a")
                }
            }
            .buttonStyle(.secondary)
            .disabled(schedulerEngine.backgroundTasks[schedule.id] != nil)

            // Draft History
            if !session.draftHistory.isEmpty {
                DraftHistoryView(schedule: schedule, session: session, showSendTarget: $showSendTarget, sendTargetDraft: $sendTargetDraft)
            }

            // Conversation (newest on top)
            let allMessages = buildConversationMessages()
            let latestIds = buildLatestMessageIds()
            let imageIndexMap = buildImageIndexMap(from: allMessages)
            if !allMessages.isEmpty {
                let totalPages = max(1, Int(ceil(Double(allMessages.count) / Double(pageSize))))
                let safeCurrentPage = min(conversationPage, totalPages - 1)
                let start = safeCurrentPage * pageSize
                let end = min(start + pageSize, allMessages.count)
                let pagedMessages = Array(allMessages[start..<end])

                HStack {
                    sectionHeader("Conversation", icon: "bubble.left.and.bubble.right")
                    Spacer()
                    if totalPages > 1 {
                        conversationPagination(total: allMessages.count, totalPages: totalPages, currentPage: safeCurrentPage)
                    }
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(pagedMessages.enumerated()), id: \.element.id) { index, message in
                        let globalIndex = start + index
                        let isLatest = latestIds.contains(message.ts ?? "")
                        let isOwner = message.user == appVM.slackUserId
                        let nextIsLatest = globalIndex + 1 < allMessages.count ? latestIds.contains(allMessages[globalIndex + 1].ts ?? "") : false
                        let isLastNew = isLatest && !nextIsLatest

                        messageRow(message: message, isLatest: isLatest, isOwner: isOwner, imageIndexMap: imageIndexMap)

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

                if totalPages > 1 {
                    conversationPagination(total: allMessages.count, totalPages: totalPages, currentPage: safeCurrentPage)
                }
            }
        }
    }

    private func completedActionView(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                completedActionLabel(session),
                icon: completedActionIcon(session)
            )

            if let sent = session.sentMessage {
                Text(sent)
                    .padding(12)
                    .background(.green.opacity(0.1))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            } else if session.finalAction == .ignored, let draft = session.draftReply {
                Text(draft)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.05))
                    .cornerRadius(8)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func completedActionLabel(_ session: Session) -> String {
        switch session.finalAction {
        case .sent: return "Sent"
        case .ignored: return "Ignored"
        case .skipped: return "Skipped"
        default: return "Pending"
        }
    }

    private func completedActionIcon(_ session: Session) -> String {
        switch session.finalAction {
        case .sent: return "paperplane.fill"
        case .ignored: return "xmark.circle"
        case .skipped: return "forward.fill"
        default: return "clock"
        }
    }

    private func messageRow(message: SlackMessage, isLatest: Bool, isOwner: Bool, imageIndexMap: [String: Int] = [:]) -> some View {
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
                    messageImages(message.imageFiles, imageIndexMap: imageIndexMap)
                }

                HStack(spacing: 8) {
                    if let date = slackTsToDate(message.ts) {
                        Text(Self.messageTimestampFormatter.string(from: date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if schedule.type != .thread, let ts = message.ts,
                       let link = appVM.slackMessageLink(channelId: schedule.channelId, messageTs: ts) {
                        Button {
                            monitorThreadLink = link
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                Text("Monitor Thread")
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
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

    private func messageImages(_ files: [SlackFile], imageIndexMap: [String: Int]) -> some View {
        HStack(spacing: 6) {
            ForEach(files) { file in
                SlackImageView(file: file, slackService: appVM.slackService, onTap: {
                    if let idx = imageIndexMap[file.id] {
                        imagePreviewIndex = idx
                        showImagePreview = true
                    }
                })
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

    private var autoSendToggle: some View {
        HStack(spacing: 12) {
            // Auto Send toggle
            HStack(spacing: 8) {
                if schedule.autoSend {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.white)
                        .font(.caption)
                }
                Toggle(isOn: Binding(
                    get: { schedule.autoSend },
                    set: { newValue in
                        var updated = schedule
                        updated.autoSend = newValue
                        if newValue { updated.signDrafts = true }
                        scheduleStore.updateSchedule(updated)
                    }
                )) {
                    Text("Auto Send")
                        .font(.caption.bold())
                        .foregroundStyle(schedule.autoSend ? .white : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(schedule.autoSend ? Color.blue : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(schedule.autoSend ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.2), value: schedule.autoSend)

            // Sign Drafts toggle
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { schedule.signDrafts },
                    set: { newValue in
                        var updated = schedule
                        updated.signDrafts = newValue
                        scheduleStore.updateSchedule(updated)
                    }
                )) {
                    Text("Signature")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func conversationPagination(total: Int, totalPages: Int, currentPage: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(total) messages")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                conversationPage = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage == 0)
            .buttonStyle(.plain)

            Text("Page \(currentPage + 1) / \(totalPages)")
                .font(.caption)
                .frame(minWidth: 70)

            Button {
                conversationPage = min(totalPages - 1, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= totalPages - 1)
            .buttonStyle(.plain)
        }
        .font(.caption)
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

// MARK: - Keyboard Navigation Modifier

private struct KeyboardNavModifier: ViewModifier {
    let schedule: Schedule
    @Binding var showEditSheet: Bool
    @Binding var showDeleteConfirm: Bool
    @Binding var showActiveReply: Bool
    @Binding var showEditSend: Bool
    @Binding var showRewrite: Bool
    @Binding var triggerGenerateDraft: Bool
    let scheduleStore: ScheduleStore
    let schedulerEngine: SchedulerEngine
    @ObservedObject var keyboardNav: KeyboardNavigationState

    func body(content: Content) -> some View {
        content
            .onChange(of: keyboardNav.editSelectedSchedule) { _, edit in
                if edit {
                    showEditSheet = true
                    keyboardNav.editSelectedSchedule = false
                }
            }
            .onChange(of: keyboardNav.activeReply) { _, reply in
                if reply {
                    showActiveReply = true
                    keyboardNav.activeReply = false
                }
            }
            .onChange(of: keyboardNav.editAndSend) { _, val in
                if val {
                    if !schedule.autoSend {
                        showEditSend = true
                    }
                    keyboardNav.editAndSend = false
                }
            }
            .onChange(of: keyboardNav.rewriteDraft) { _, val in
                if val {
                    if !schedule.autoSend {
                        if schedule.latestSession?.finalAction == .skipped {
                            triggerGenerateDraft = true
                        } else {
                            showRewrite = true
                        }
                    }
                    keyboardNav.rewriteDraft = false
                }
            }
            .onChange(of: keyboardNav.ignoreDraft) { _, val in
                if val {
                    if !schedule.autoSend {
                        // Ignore the current draft directly
                        var updated = schedule
                        if var lastSession = updated.sessions.last {
                            lastSession.finalAction = .ignored
                            updated.sessions[updated.sessions.count - 1] = lastSession
                        }
                        scheduleStore.updateSchedule(updated)
                    }
                    keyboardNav.ignoreDraft = false
                }
            }
            .onChange(of: keyboardNav.deleteSelectedSchedule) { _, del in
                if del {
                    showDeleteConfirm = true
                    keyboardNav.confirmingDelete = true
                    keyboardNav.deleteSelectedSchedule = false
                }
            }
            .onChange(of: keyboardNav.confirmDeleteAnswer) { _, answer in
                guard let answer else { return }
                if answer {
                    schedulerEngine.stopSchedule(schedule.id)
                    scheduleStore.deleteSchedule(schedule)
                }
                showDeleteConfirm = false
                keyboardNav.confirmingDelete = false
                keyboardNav.confirmDeleteAnswer = nil
            }
            .overlay {
                if showDeleteConfirm {
                    DeleteConfirmOverlay(
                        name: schedule.name,
                        onConfirm: {
                            schedulerEngine.stopSchedule(schedule.id)
                            scheduleStore.deleteSchedule(schedule)
                            showDeleteConfirm = false
                            keyboardNav.confirmingDelete = false
                        },
                        onCancel: {
                            showDeleteConfirm = false
                            keyboardNav.confirmingDelete = false
                        }
                    )
                }
            }
    }
}
