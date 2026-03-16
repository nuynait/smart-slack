import SwiftUI

struct ForcePopupView: View {
    let schedule: Schedule
    let session: Session
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var userColorStore: UserColorStore
    @State private var isSending = false
    @State private var error: String?
    @State private var showSendTarget = false
    @State private var sendTargetDraft = ""
    @State private var showEditSend = false
    @State private var showRewrite = false
    @State private var colorPickerUserId: String?
    @State private var showImagePreview = false
    @State private var imagePreviewIndex = 0

    // Auto-send countdown
    @State private var autoSendCountdown: Int = 10
    @State private var autoSendTimer: Timer?

    private var currentSession: Session? {
        scheduleStore.schedule(byId: schedule.id)?.latestSession
    }

    private var currentSchedule: Schedule? {
        scheduleStore.schedule(byId: schedule.id)
    }

    private var isAutoSend: Bool {
        currentSchedule?.autoSend ?? schedule.autoSend
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let activeSchedule = currentSchedule ?? schedule
                    let activeSession = currentSession ?? session

                    // Summary
                    if let summary = activeSession.summary {
                        sectionHeader("Summary", icon: "text.alignleft")
                        MarkdownView(text: summary)
                            .padding(12)
                            .background(.quaternary)
                            .cornerRadius(8)
                    }

                    // Memory Report
                    if let memoryReport = activeSession.memoryReport {
                        sectionHeader("Memory Updated", icon: "brain")
                        MarkdownView(text: memoryReport)
                            .padding(12)
                            .background(.purple.opacity(0.05))
                            .cornerRadius(8)
                    }

                    // Auto-send toggle
                    autoSendToggle

                    // Draft
                    if let draft = activeSession.draftReply {
                        sectionHeader("Draft Reply", icon: "pencil.and.outline")
                        Text(draft)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.blue.opacity(0.05))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }

                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    // Actions
                    if isAutoSend {
                        autoSendCountdownView
                    } else {
                        manualActions(activeSession: activeSession)

                        Divider()

                        // Rewrite button opens overlay
                        Button {
                            showRewrite = true
                        } label: {
                            Label("Rewrite", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.secondary)
                        .disabled(activeSession.draftReply == nil || isSending)
                    }

                    // Conversation (color-coded)
                    let messages = conversationMessages(from: activeSchedule)
                    let latestIds = latestMessageIds(from: activeSchedule)
                    if !messages.isEmpty {
                        sectionHeader("Conversation", icon: "bubble.left.and.bubble.right")
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                let isLatest = latestIds.contains(message.ts ?? "")
                                let isOwner = message.user == appVM.slackUserId
                                let nextIsLatest = index + 1 < messages.count ? latestIds.contains(messages[index + 1].ts ?? "") : false
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
                .padding(16)
            }
        }
        .frame(width: 650, height: 700)
        .overlay {
            if showSendTarget {
                SendTargetOverlay(schedule: currentSchedule ?? schedule, draftText: sendTargetDraft, isPresented: $showSendTarget)
            }
            if showEditSend, let activeSession = currentSession ?? Optional(session) {
                EditSendOverlay(schedule: currentSchedule ?? schedule, session: activeSession, isPresented: $showEditSend, showSendTarget: $showSendTarget, sendTargetDraft: $sendTargetDraft)
            }
            if showRewrite, let activeSession = currentSession ?? Optional(session) {
                RewriteOverlay(schedule: currentSchedule ?? schedule, session: activeSession, isPresented: $showRewrite)
            }
            if showImagePreview {
                let images = allConversationImages(from: currentSchedule ?? schedule)
                ImagePreviewOverlay(images: images, slackService: appVM.slackService, selectedIndex: $imagePreviewIndex, isPresented: $showImagePreview)
            }
        }
        .onChange(of: showSendTarget) { _, showing in
            if !showing, let sched = currentSchedule,
               sched.latestSession?.finalAction == .sent {
                notificationService.forcePopupScheduleId = nil
            }
        }
        .onChange(of: showEditSend) { _, showing in
            if !showing, let sched = currentSchedule,
               sched.latestSession?.finalAction == .sent {
                notificationService.forcePopupScheduleId = nil
            }
        }
        .onChange(of: isAutoSend) { _, autoSend in
            let activeSession = currentSession ?? session
            if autoSend && activeSession.finalAction == .pending && activeSession.draftReply != nil {
                startAutoSendCountdown()
            } else {
                cancelAutoSendCountdown()
            }
        }
        .onAppear {
            if isAutoSend {
                let activeSession = currentSession ?? session
                if activeSession.finalAction == .pending && activeSession.draftReply != nil {
                    startAutoSendCountdown()
                }
            }
            resolveUserNames()
        }
        .onDisappear {
            cancelAutoSendCountdown()
        }
        // Enter key sends draft (when not in text field)
        .onKeyPress(.return) {
            let activeSession = currentSession ?? session
            guard activeSession.finalAction == .pending,
                  activeSession.draftReply != nil,
                  !isSending, !showEditSend, !showRewrite, !showSendTarget else {
                return .ignored
            }
            Task { await sendAndDismiss() }
            return .handled
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                Text(schedule.name)
                    .font(.title3.bold())
                Spacer()
            }

            let sched = currentSchedule ?? schedule
            HStack(spacing: 12) {
                Label(sched.channelName, systemImage: channelIcon)
                    .font(.caption)

                Label("Every \(formatInterval(sched.intervalSeconds))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("Initial: \(sched.initialMessageCount)", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("Created: \(sched.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastRun = sched.lastRun {
                    Label("Last run: \(lastRun.relativeFormatted)", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Filter banner
            if let filter = sched.filterSummary {
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

            // Memory banner
            if let memorySummary = sched.memorySummary {
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
        .padding()
        .background(.quaternary)
    }

    // MARK: - Auto-send Toggle

    private var autoSendToggle: some View {
        HStack(spacing: 8) {
            if isAutoSend {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.white)
                    .font(.caption)
            }
            Toggle(isOn: Binding(
                get: { currentSchedule?.autoSend ?? schedule.autoSend },
                set: { newValue in
                    var updated = currentSchedule ?? schedule
                    updated.autoSend = newValue
                    scheduleStore.updateSchedule(updated)
                }
            )) {
                Text("Auto Send")
                    .font(.caption.bold())
                    .foregroundStyle(isAutoSend ? .white : .secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isAutoSend ? Color.blue : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isAutoSend ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isAutoSend)
    }

    // MARK: - Auto-send Countdown

    private var autoSendCountdownView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if isSending {
                    ProgressView().controlSize(.small)
                    Text("Sending...")
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "timer")
                        .foregroundStyle(.blue)
                    Text("Auto-sending in \(autoSendCountdown)s")
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)

                    ProgressView(value: Double(10 - autoSendCountdown), total: 10)
                        .tint(.blue)
                        .frame(maxWidth: 120)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.08))
            .cornerRadius(8)

            if !isSending {
                HStack(spacing: 12) {
                    Button {
                        Task { await sendAndDismiss() }
                    } label: {
                        Label("Send Now (Enter)", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.primary)

                    Button {
                        ignore()
                    } label: {
                        Label("Ignore", systemImage: "xmark")
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Manual Actions

    private func manualActions(activeSession: Session) -> some View {
        HStack(spacing: 12) {
            Button {
                let sched = currentSchedule ?? schedule
                let draft = activeSession.draftReply ?? ""
                if sched.type != .thread {
                    sendTargetDraft = draft
                    showSendTarget = true
                } else {
                    Task { await sendAndDismiss() }
                }
            } label: {
                if isSending {
                    ProgressView().controlSize(.small)
                } else {
                    let sched = currentSchedule ?? schedule
                    if sched.type != .thread {
                        Label("Send to...", systemImage: "paperplane.fill")
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
            }
            .buttonStyle(.primary)
            .disabled(activeSession.draftReply == nil || isSending)

            Button {
                showEditSend = true
            } label: {
                Label("Edit & Send", systemImage: "pencil")
            }
            .buttonStyle(.secondary)
            .disabled(activeSession.draftReply == nil || isSending)

            Button {
                ignore()
            } label: {
                Label("Ignore", systemImage: "xmark")
            }
            .buttonStyle(.secondary)
            .disabled(isSending)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private var channelIcon: String {
        let sched = currentSchedule ?? schedule
        switch sched.type {
        case .channel: return "number"
        case .thread: return "bubble.left.and.bubble.right"
        case .dm: return "person"
        case .dmgroup: return "person.3"
        }
    }

    private func formatInterval(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        if remaining == 0 { return "\(minutes)m" }
        return "\(minutes)m \(remaining)s"
    }

    // MARK: - Conversation

    private func conversationMessages(from schedule: Schedule) -> [SlackMessage] {
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

    private func latestMessageIds(from schedule: Schedule) -> Set<String> {
        guard let latest = schedule.latestSession else { return [] }
        return Set(latest.messages.compactMap(\.ts))
    }

    private func allConversationImages(from schedule: Schedule) -> [SlackFile] {
        conversationMessages(from: schedule).flatMap(\.imageFiles)
    }

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
                    messageImages(message.imageFiles, from: currentSchedule ?? schedule)
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

    private func messageImages(_ files: [SlackFile], from schedule: Schedule) -> some View {
        let allImages = allConversationImages(from: schedule)
        return HStack(spacing: 6) {
            ForEach(files) { file in
                SlackImageView(file: file, slackService: appVM.slackService, onTap: {
                    if let idx = allImages.firstIndex(where: { $0.id == file.id }) {
                        imagePreviewIndex = idx
                        showImagePreview = true
                    }
                })
            }
        }
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

    private func resolveUserNames() {
        let messages = conversationMessages(from: currentSchedule ?? schedule)
        var allUserIds = messages.compactMap(\.user)
        let mentionPattern = /<@(U[A-Z0-9]+)>/
        for msg in messages {
            guard let text = msg.text else { continue }
            for match in text.matches(of: mentionPattern) {
                allUserIds.append(String(match.1))
            }
        }
        appVM.resolveUserNames(ids: allUserIds)
    }

    // MARK: - Auto-send Timer

    private func startAutoSendCountdown() {
        cancelAutoSendCountdown()
        autoSendCountdown = 10
        autoSendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                autoSendCountdown -= 1
                if autoSendCountdown <= 0 {
                    cancelAutoSendCountdown()
                    await sendAndDismiss()
                }
            }
        }
    }

    private func cancelAutoSendCountdown() {
        autoSendTimer?.invalidate()
        autoSendTimer = nil
        autoSendCountdown = 10
    }

    // MARK: - Actions

    private func sendAndDismiss() async {
        guard let slackService = appVM.slackService,
              let sched = currentSchedule,
              let activeSession = currentSession,
              let draft = activeSession.draftReply else { return }
        isSending = true
        error = nil

        do {
            let threadTs = sched.type == .thread ? sched.threadTs : nil
            _ = try await slackService.postMessage(
                channelId: sched.channelId,
                text: draft,
                threadTs: threadTs
            )

            var updated = sched
            if var lastSession = updated.sessions.last {
                lastSession.finalAction = .sent
                lastSession.sentMessage = draft
                updated.sessions[updated.sessions.count - 1] = lastSession
            }
            scheduleStore.updateSchedule(updated)
            cancelAutoSendCountdown()
            notificationService.forcePopupScheduleId = nil
        } catch {
            self.error = error.localizedDescription
        }

        isSending = false
    }

    private func ignore() {
        guard let sched = currentSchedule else { return }
        var updated = sched
        if var lastSession = updated.sessions.last {
            lastSession.finalAction = .ignored
            updated.sessions[updated.sessions.count - 1] = lastSession
        }
        scheduleStore.updateSchedule(updated)
        cancelAutoSendCountdown()
        notificationService.forcePopupScheduleId = nil
    }
}
