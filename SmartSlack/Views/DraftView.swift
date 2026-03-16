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
    @Binding var triggerGenerateDraft: Bool
    @State private var isSending = false
    @State private var error: String?

    @State private var isGenerating = false

    // Auto-send countdown
    @State private var autoSendCountdown: Int = 10
    @State private var autoSendTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.finalAction == .skipped {
                skippedView
            } else {
                draftView
            }
        }
        .onChange(of: triggerGenerateDraft) { _, trigger in
            if trigger {
                triggerGenerateDraft = false
                Task { await generateDraft() }
            }
        }
        .onChange(of: schedule.autoSend) { _, autoSend in
            if autoSend && session.finalAction == .pending && session.draftReply != nil {
                startAutoSendCountdown()
            } else {
                cancelAutoSendCountdown()
            }
        }
        .onAppear {
            if schedule.autoSend && session.finalAction == .pending && session.draftReply != nil {
                startAutoSendCountdown()
            }
        }
        .onDisappear {
            cancelAutoSendCountdown()
        }
    }

    private var skippedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Label("Skipped", systemImage: "forward.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }

            if let reason = session.skipReason {
                Text(reason)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.05))
                    .cornerRadius(8)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await generateDraft() }
                } label: {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack(spacing: 4) {
                            Label("Generate Draft", systemImage: "arrow.triangle.2.circlepath")
                            KeyboardHintView(key: "r")
                        }
                    }
                }
                .buttonStyle(.primary)
                .disabled(isGenerating)

                Button {
                    ignore()
                } label: {
                    HStack(spacing: 4) {
                        Label("Ignore", systemImage: "xmark")
                        KeyboardHintView(key: "i")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(isGenerating)
            }
        }
    }

    private var draftView: some View {
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

            if schedule.autoSend {
                autoSendCountdownView
            } else {
                manualActionButtons
            }
        }
    }

    private var autoSendCountdownView: some View {
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
    }

    private var manualActionButtons: some View {
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

    // MARK: - Auto-send Timer

    private func startAutoSendCountdown() {
        cancelAutoSendCountdown()
        autoSendCountdown = 10
        autoSendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                autoSendCountdown -= 1
                if autoSendCountdown <= 0 {
                    cancelAutoSendCountdown()
                    await autoSend()
                }
            }
        }
    }

    private func cancelAutoSendCountdown() {
        autoSendTimer?.invalidate()
        autoSendTimer = nil
        autoSendCountdown = 10
    }

    private func autoSend() async {
        guard let draft = session.draftReply else { return }
        let threadTs = schedule.type == .thread ? schedule.threadTs : nil
        await send(draft: draft, threadTs: threadTs)
    }

    // MARK: - Actions

    private func send(draft: String, threadTs: String? = nil) async {
        guard let slackService = appVM.slackService else { return }
        isSending = true
        error = nil

        do {
            let ts = threadTs ?? (schedule.type == .thread ? schedule.threadTs : nil)
            _ = try await slackService.postMessage(
                channelId: schedule.channelId,
                text: draft,
                threadTs: ts
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

    private func generateDraft() async {
        isGenerating = true
        error = nil

        do {
            let allSummaries = schedule.sessions.compactMap(\.summary)

            let result = try await ClaudeService.unskipRewrite(
                messages: session.messages,
                allSummaries: allSummaries,
                originalPrompt: schedule.prompt,
                channelName: schedule.channelName,
                scheduleId: schedule.id,
                ownerUserId: appVM.slackUserId,
                ownerDisplayName: appVM.slackUserDisplayName,
                userNames: appVM.userNameCache
            )

            var updated = schedule
            if var lastSession = updated.sessions.last(where: { $0.sessionId == session.sessionId }),
               let idx = updated.sessions.firstIndex(where: { $0.sessionId == session.sessionId }) {
                lastSession.draftReply = result.draftReply
                lastSession.summary = result.summary
                lastSession.finalAction = .pending
                lastSession.skipReason = nil
                updated.sessions[idx] = lastSession
            }
            scheduleStore.updateSchedule(updated)
        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
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
