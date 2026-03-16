import SwiftUI

struct DraftView: View {
    let schedule: Schedule
    let session: Session
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @Binding var showEditSend: Bool
    @Binding var showRewrite: Bool
    @Binding var showSendTarget: Bool
    @Binding var sendTargetDraft: String
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
                    let draft = session.draftReply ?? ""
                    if schedule.type != .thread {
                        sendTargetDraft = draft
                        showSendTarget = true
                    } else {
                        Task { await send(draft: draft) }
                    }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else if schedule.type != .thread {
                        Label("Send to...", systemImage: "paperplane.fill")
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.primary)
                .disabled(session.draftReply == nil || isSending)

                Button {
                    showEditSend = true
                } label: {
                    HStack(spacing: 4) {
                        Label("Edit & Send", systemImage: "pencil")
                        KeyboardHintView(key: "e")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(session.draftReply == nil || isSending)

                Button {
                    showRewrite = true
                } label: {
                    HStack(spacing: 4) {
                        Label("Rewrite", systemImage: "arrow.triangle.2.circlepath")
                        KeyboardHintView(key: "r")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(session.draftReply == nil || isSending)

                Button {
                    ignore()
                } label: {
                    HStack(spacing: 4) {
                        Label("Ignore", systemImage: "xmark")
                        KeyboardHintView(key: "i")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(isSending)
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
}
