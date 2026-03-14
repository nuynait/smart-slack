import SwiftUI

struct DraftHistoryView: View {
    let schedule: Schedule
    let session: Session
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var sendingId: UUID?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Previous Drafts", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            ForEach(session.draftHistory.reversed()) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.timestamp.shortFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let prompt = entry.rewritePrompt {
                            Text("Rewrite: \(prompt)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        if session.finalAction == .pending {
                            Button {
                                Task { await send(entry.draft) }
                            } label: {
                                if sendingId == entry.id {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Text("Send")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.smallSecondary)
                            .disabled(sendingId != nil)
                        }
                    }

                    Text(entry.draft)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(.quaternary)
                .cornerRadius(6)
            }
        }
    }

    private func send(_ draft: String) async {
        guard let slackService = appVM.slackService else { return }
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

        sendingId = nil
    }
}
