import SwiftUI

struct ForcePopupView: View {
    let schedule: Schedule
    let session: Session
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var notificationService: NotificationService
    @State private var rewritePrompt = ""
    @State private var isRewriting = false
    @State private var isSending = false
    @State private var error: String?

    private var currentSession: Session? {
        scheduleStore.schedule(byId: schedule.id)?.latestSession
    }

    private var currentSchedule: Schedule? {
        scheduleStore.schedule(byId: schedule.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                Text(schedule.name)
                    .font(.title3.bold())
                Spacer()
                Text(schedule.channelName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.quaternary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary
                    let activeSession = currentSession ?? session
                    if let summary = activeSession.summary {
                        Label("Summary", systemImage: "text.alignleft")
                            .font(.headline)
                        MarkdownView(text: summary)
                            .padding(12)
                            .background(.quaternary)
                            .cornerRadius(8)
                    }

                    // Draft
                    if let draft = activeSession.draftReply {
                        Label("Draft Reply", systemImage: "pencil.and.outline")
                            .font(.headline)
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
                    HStack(spacing: 12) {
                        Button {
                            Task { await send() }
                        } label: {
                            if isSending {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Send", systemImage: "paperplane.fill")
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(isSending || isRewriting)

                        Button {
                            ignore()
                        } label: {
                            Label("Ignore", systemImage: "xmark")
                        }
                        .buttonStyle(.secondary)
                        .disabled(isSending || isRewriting)
                    }

                    Divider()

                    // Rewrite
                    HStack {
                        TextField("Rewrite instructions...", text: $rewritePrompt)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await rewrite() }
                        } label: {
                            if isRewriting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Rewrite", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(rewritePrompt.isEmpty || isRewriting || isSending)
                    }

                    // Recent conversation
                    let activeSchedule = currentSchedule ?? schedule
                    let messages = recentMessages(from: activeSchedule)
                    if !messages.isEmpty {
                        Label("Recent Conversation", systemImage: "bubble.left.and.bubble.right")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(messages) { message in
                                HStack(alignment: .top, spacing: 8) {
                                    let userId = message.user ?? "?"
                                    Text(appVM.displayName(for: userId))
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .trailing)
                                    Text(message.text ?? "")
                                        .font(.callout)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 600, height: 650)
    }

    private func recentMessages(from schedule: Schedule) -> [SlackMessage] {
        guard let latest = schedule.latestSession else { return [] }
        return Array(latest.messages.suffix(10))
    }

    private func send() async {
        guard let slackService = appVM.slackService,
              let sched = currentSchedule else { return }
        isSending = true
        error = nil

        do {
            let activeSession = currentSession ?? session
            let threadTs = sched.type == .thread ? sched.threadTs : nil
            _ = try await slackService.postMessage(
                channelId: sched.channelId,
                text: activeSession.draftReply ?? "",
                threadTs: threadTs
            )

            var updated = sched
            if var lastSession = updated.sessions.last {
                lastSession.finalAction = .sent
                lastSession.sentMessage = activeSession.draftReply
                updated.sessions[updated.sessions.count - 1] = lastSession
            }
            scheduleStore.updateSchedule(updated)
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
        notificationService.forcePopupScheduleId = nil
    }

    private func rewrite() async {
        guard let sched = currentSchedule,
              let activeSession = currentSession else { return }
        isRewriting = true
        error = nil

        do {
            let allSummaries = sched.sessions.compactMap(\.summary)
            var currentHistory = activeSession.draftHistory
            if let currentDraft = activeSession.draftReply {
                currentHistory.append(DraftEntry(
                    id: UUID(),
                    draft: currentDraft,
                    timestamp: Date(),
                    rewritePrompt: nil
                ))
            }

            let result = try await ClaudeService.rewrite(
                messages: activeSession.messages,
                allSummaries: allSummaries,
                draftHistory: currentHistory,
                originalPrompt: sched.prompt,
                rewritePrompt: rewritePrompt,
                channelName: sched.channelName,
                scheduleId: sched.id,
                ownerUserId: appVM.slackUserId,
                ownerDisplayName: appVM.slackUserDisplayName,
                userNames: appVM.userNameCache
            )

            var updated = sched
            if var lastSession = updated.sessions.last {
                if let oldDraft = lastSession.draftReply {
                    lastSession.draftHistory.append(DraftEntry(
                        id: UUID(),
                        draft: oldDraft,
                        timestamp: Date(),
                        rewritePrompt: rewritePrompt
                    ))
                }
                lastSession.draftReply = result.draftReply
                lastSession.summary = result.summary
                updated.sessions[updated.sessions.count - 1] = lastSession
            }
            scheduleStore.updateSchedule(updated)
            rewritePrompt = ""
        } catch {
            self.error = error.localizedDescription
        }

        isRewriting = false
    }
}
