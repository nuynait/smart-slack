import SwiftUI

struct DraftView: View {
    let schedule: Schedule
    let session: Session
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var rewritePrompt = ""
    @State private var isRewriting = false
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Draft Reply", systemImage: "pencil.and.outline")
                .font(.headline)

            if let draft = session.draftReply {
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

            HStack(spacing: 12) {
                Button {
                    Task { await send(draft: session.draftReply ?? "") }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.draftReply == nil || isSending || isRewriting)

                Button {
                    ignore()
                } label: {
                    Label("Ignore", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .disabled(isSending || isRewriting)
            }

            Divider()

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
                .buttonStyle(.bordered)
                .disabled(rewritePrompt.isEmpty || isRewriting || isSending)
            }
        }
    }

    private func send(draft: String) async {
        guard let slackService = appVM.slackService else { return }
        isSending = true
        error = nil

        do {
            let threadTs = schedule.type == .thread ? schedule.threadTs : nil
            _ = try await slackService.postMessage(
                channelId: schedule.channelId,
                text: draft,
                threadTs: threadTs
            )

            var updated = schedule
            if var lastSession = updated.sessions.last {
                lastSession.finalAction = .sent
                lastSession.sentMessage = draft
                updated.sessions[updated.sessions.count - 1] = lastSession
            }
            scheduleStore.updateSchedule(updated)
        } catch {
            self.error = error.localizedDescription
        }

        isSending = false
    }

    private func ignore() {
        var updated = schedule
        if var lastSession = updated.sessions.last {
            lastSession.finalAction = .ignored
            updated.sessions[updated.sessions.count - 1] = lastSession
        }
        scheduleStore.updateSchedule(updated)
    }

    private func rewrite() async {
        isRewriting = true
        error = nil

        do {
            let allSummaries = schedule.sessions.compactMap(\.summary)
            var currentHistory = session.draftHistory
            if let currentDraft = session.draftReply {
                currentHistory.append(DraftEntry(
                    id: UUID(),
                    draft: currentDraft,
                    timestamp: Date(),
                    rewritePrompt: nil
                ))
            }

            let result = try await ClaudeService.rewrite(
                messages: session.messages,
                allSummaries: allSummaries,
                draftHistory: currentHistory,
                originalPrompt: schedule.prompt,
                rewritePrompt: rewritePrompt,
                channelName: schedule.channelName
            )

            var updated = schedule
            if var lastSession = updated.sessions.last {
                // Move current draft to history
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
