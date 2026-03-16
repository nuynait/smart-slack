import SwiftUI

struct AddScheduleFromLinkView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @EnvironmentObject var promptStore: PromptStore
    @Environment(\.dismiss) private var dismiss

    var initialLink: String = ""
    var initialAsThread: Bool = false

    @State private var link = ""
    @State private var name = ""
    @State private var intervalSeconds: Double = 300
    @State private var prompt = ""
    @State private var initialMessageCount = 5
    @State private var notificationMode: NotificationMode = .macosNotification
    @State private var error: String?
    @State private var isResolving = false
    @State private var resolved: ResolvedLink?
    @FocusState private var isLinkFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("New Schedule from Link")
                .font(.title2.bold())
                .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Slack Message Link")
                            .font(.headline)
                        TextField("https://workspace.slack.com/archives/C.../p...", text: $link)
                            .textFieldStyle(.roundedBorder)
                            .focused($isLinkFocused)
                            .onSubmit { Task { await resolveLink() } }
                            .onChange(of: link) { _, _ in
                                resolved = nil
                            }
                            .onChange(of: isLinkFocused) { _, focused in
                                if !focused && !link.isEmpty && resolved == nil {
                                    Task { await resolveLink() }
                                }
                            }
                    }
                    .formCard()

                    if isResolving {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Resolving link...")
                                .foregroundStyle(.secondary)
                        }
                        .formCard()
                    }

                    if let resolved {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Resolved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.statusActive)
                                .font(.headline)

                            HStack(spacing: 12) {
                                Label(resolved.typeName, systemImage: resolved.typeIcon)
                                    .font(.subheadline)
                                Label(resolved.channelName, systemImage: "number")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if resolved.type == .thread {
                                Label("Thread: \(resolved.threadTs ?? "")", systemImage: "bubble.left.and.bubble.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if resolved.type == .thread, resolved.messageTs != nil {
                                Button {
                                    Task { await convertToOriginalType() }
                                } label: {
                                    Label("Revert to \(resolved.channelName)", systemImage: "arrow.uturn.backward")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            } else if resolved.type != .thread, resolved.messageTs != nil {
                                Button {
                                    convertToThread()
                                } label: {
                                    Label("Monitor as Thread", systemImage: "bubble.left.and.bubble.right")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }
                        }
                        .formCard()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.headline)
                        TextField("Schedule name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .formCard()

                    IntervalPickerView(intervalSeconds: $intervalSeconds)
                        .formCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Initial Message Count")
                            .font(.headline)
                        Text("How many recent messages to include on the first check")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $initialMessageCount) {
                            ForEach([1, 5, 10, 15, 20, 25, 30], id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .formCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification Mode")
                            .font(.headline)
                        Picker("", selection: $notificationMode) {
                            Text("Notification").tag(NotificationMode.macosNotification)
                            Text("Force Popup").tag(NotificationMode.forcePopup)
                            Text("Quiet").tag(NotificationMode.quiet)
                        }
                        .pickerStyle(.segmented)
                        Text(notificationModeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .formCard()

                    PromptInputView(prompt: $prompt)

                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(16)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if resolved == nil {
                    Button("Resolve Link") { Task { await resolveLink() } }
                        .buttonStyle(.secondary)
                        .disabled(link.isEmpty || isResolving)
                }

                Button("Create") { create() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolved == nil || name.isEmpty || prompt.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 680)
        .onAppear {
            if !initialLink.isEmpty && link.isEmpty {
                link = initialLink
                Task { await resolveLink() }
            }
        }
    }

    // MARK: - Link Parsing

    private func resolveLink() async {
        guard let slackService = appVM.slackService else { return }
        error = nil
        isResolving = true
        resolved = nil

        guard let parsed = parseSlackLink(link) else {
            error = "Invalid Slack message link. Expected format: https://workspace.slack.com/archives/CHANNEL_ID/pTIMESTAMP"
            isResolving = false
            return
        }

        do {
            let channel = try await slackService.conversationsInfo(channelId: parsed.channelId)

            let type: ScheduleType
            var channelName = channel.displayName
            if parsed.threadTs != nil {
                type = .thread
            } else if channel.isIm == true {
                type = .dm
                // Resolve DM user name
                if let userId = channel.user,
                   let userInfo = try? await slackService.usersInfo(userId: userId) {
                    channelName = userInfo.profile?.displayName.flatMap({ $0.isEmpty ? nil : $0 })
                        ?? userInfo.profile?.realName.flatMap({ $0.isEmpty ? nil : $0 })
                        ?? userInfo.realName
                        ?? userInfo.name
                        ?? channelName
                }
            } else if channel.isMpim == true {
                type = .dmgroup
            } else {
                type = .channel
            }

            resolved = ResolvedLink(
                channelId: parsed.channelId,
                channelName: channelName,
                type: type,
                threadTs: parsed.threadTs,
                messageTs: parsed.messageTs
            )

            // Auto-convert to thread if requested (e.g. from "Monitor Thread" button)
            if initialAsThread && type != .thread {
                convertToThread()
            }

            if name.isEmpty {
                name = channelName
            }
        } catch {
            self.error = error.localizedDescription
        }

        isResolving = false
    }

    private func convertToThread() {
        guard var r = resolved, r.type != .thread, let ts = r.messageTs else { return }
        r.type = .thread
        r.threadTs = ts
        resolved = r
    }

    private func convertToOriginalType() async {
        // Re-resolve to get the original type back
        guard let parsed = parseSlackLink(link),
              let slackService = appVM.slackService else { return }
        do {
            let channel = try await slackService.conversationsInfo(channelId: parsed.channelId)
            var r = resolved
            if channel.isIm == true {
                r?.type = .dm
            } else if channel.isMpim == true {
                r?.type = .dmgroup
            } else {
                r?.type = .channel
            }
            r?.threadTs = parsed.threadTs
            resolved = r
        } catch {}
    }

    private struct ParsedLink {
        let channelId: String
        let messageTs: String
        let threadTs: String?
    }

    private func parseSlackLink(_ link: String) -> ParsedLink? {
        // Format: https://workspace.slack.com/archives/CHANNEL_ID/pTIMESTAMP
        // Thread: ...?thread_ts=TIMESTAMP&cid=CHANNEL_ID
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host,
              host.contains("slack.com") else { return nil }

        let pathComponents = url.pathComponents
        // pathComponents: ["/", "archives", "CHANNEL_ID", "pTIMESTAMP"]
        guard let archivesIdx = pathComponents.firstIndex(of: "archives"),
              archivesIdx + 2 < pathComponents.count else { return nil }

        let channelId = pathComponents[archivesIdx + 1]
        let messageComponent = pathComponents[archivesIdx + 2]

        // Message ts: p1234567890123456 -> 1234567890.123456
        guard messageComponent.hasPrefix("p") else { return nil }
        let rawTs = String(messageComponent.dropFirst())
        let messageTs: String
        if rawTs.count > 6 {
            let idx = rawTs.index(rawTs.endIndex, offsetBy: -6)
            messageTs = rawTs[rawTs.startIndex..<idx] + "." + rawTs[idx...]
        } else {
            messageTs = rawTs
        }

        // Check for thread_ts in query params
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let threadTs = components?.queryItems?.first(where: { $0.name == "thread_ts" })?.value

        return ParsedLink(
            channelId: channelId,
            messageTs: messageTs,
            threadTs: threadTs ?? (link.contains("thread_ts") ? nil : nil)
        )
    }

    // MARK: - Create

    private func create() {
        guard let resolved else { return }

        let schedule = Schedule(
            id: UUID(),
            name: name,
            type: resolved.type,
            channelId: resolved.channelId,
            threadTs: resolved.threadTs,
            channelName: resolved.channelName,
            prompt: prompt,
            intervalSeconds: Int(intervalSeconds),
            status: .active,
            createdAt: Date(),
            lastRun: nil,
            lastMessageTs: nil,
            sessions: [],
            initialMessageCount: initialMessageCount,
            notificationMode: notificationMode
        )

        scheduleStore.saveSchedule(schedule)
        schedulerEngine.startSchedule(schedule)

        // Save prompt to history and generate tags
        let savedPrompt = promptStore.addPrompt(text: prompt)
        Task { await promptStore.generateTags(for: savedPrompt.id) }

        dismiss()
    }

    private var notificationModeDescription: String {
        switch notificationMode {
        case .macosNotification:
            return "Show a macOS notification when Claude responds. Click to jump to the schedule."
        case .forcePopup:
            return "Show an always-on-top popup with summary and draft. Must send or ignore to dismiss."
        case .quiet:
            return "No notification. Check drafts manually from the sidebar."
        }
    }

}

// MARK: - Resolved Link

struct ResolvedLink {
    let channelId: String
    let channelName: String
    var type: ScheduleType
    var threadTs: String?
    let messageTs: String?

    var typeName: String {
        switch type {
        case .channel: return "Channel"
        case .thread: return "Thread"
        case .dm: return "DM"
        case .dmgroup: return "Group DM"
        }
    }

    var typeIcon: String {
        switch type {
        case .channel: return "number"
        case .thread: return "bubble.left.and.bubble.right"
        case .dm: return "person"
        case .dmgroup: return "person.3"
        }
    }
}
