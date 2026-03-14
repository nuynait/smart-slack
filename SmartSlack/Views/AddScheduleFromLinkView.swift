import SwiftUI

struct AddScheduleFromLinkView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var name = ""
    @State private var intervalSeconds: Double = 300
    @State private var prompt = ""
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
                        Text("Prompt")
                            .font(.headline)
                        TextEditor(text: $prompt)
                            .frame(minHeight: 80)
                            .font(.body)
                    }
                    .formCard()

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
        .frame(width: 500, height: 580)
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
                threadTs: parsed.threadTs
            )

            if name.isEmpty {
                name = channelName
            }
        } catch {
            self.error = error.localizedDescription
        }

        isResolving = false
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
            sessions: []
        )

        scheduleStore.saveSchedule(schedule)
        schedulerEngine.startSchedule(schedule)
        dismiss()
    }

}

// MARK: - Resolved Link

struct ResolvedLink {
    let channelId: String
    let channelName: String
    let type: ScheduleType
    let threadTs: String?

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
