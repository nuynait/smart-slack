import SwiftUI

struct RewriteOverlay: View {
    let schedule: Schedule
    let session: Session
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @Binding var isPresented: Bool
    @State private var rewritePrompt = ""
    @State private var isRewriting = false
    @State private var sentToBackground = false
    @State private var error: String?
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isRewriting { isPresented = false }
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Rewrite Draft", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Spacer()
                    if !isRewriting {
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Describe how you'd like the draft to be rewritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let currentDraft = session.draftReply {
                    Text(currentDraft)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.05))
                        .cornerRadius(6)
                        .lineLimit(4)
                }

                TextEditor(text: $rewritePrompt)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 120)
                    .focused($isPromptFocused)

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.secondary)
                    .disabled(isRewriting)
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    if isRewriting {
                        Button {
                            sentToBackground = true
                            schedulerEngine.backgroundTasks[schedule.id] = BackgroundTaskInfo(scheduleId: schedule.id, type: .rewrite)
                            appVM.notificationService.forcePopupScheduleId = nil
                            isPresented = false
                        } label: {
                            Label("Run in Background", systemImage: "arrow.down.app")
                        }
                        .buttonStyle(.secondary)
                    }

                    Button {
                        Task { await rewrite() }
                    } label: {
                        if isRewriting {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Rewriting...")
                            }
                        } else {
                            Label("Rewrite", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(rewritePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRewriting)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 5)
        }
        .onAppear {
            DispatchQueue.main.async { isPromptFocused = true }
        }
    }

    private func rewrite() async {
        isRewriting = true
        error = nil

        do {
            // Gather all conversation messages
            var seen = Set<String>()
            var allMessages: [SlackMessage] = []
            for s in schedule.sessions {
                for msg in s.messages {
                    let key = msg.ts ?? UUID().uuidString
                    if !seen.contains(key) {
                        seen.insert(key)
                        allMessages.append(msg)
                    }
                }
            }
            for msg in schedule.pendingMessages {
                let key = msg.ts ?? UUID().uuidString
                if !seen.contains(key) {
                    seen.insert(key)
                    allMessages.append(msg)
                }
            }
            allMessages.sort { ($0.ts ?? "") < ($1.ts ?? "") }

            let allSummaries = schedule.sessions.compactMap(\.summary)

            let result = try await ClaudeService.rewrite(
                messages: allMessages,
                allSummaries: allSummaries,
                draftHistory: session.draftHistory,
                originalPrompt: schedule.prompt,
                rewritePrompt: rewritePrompt,
                channelName: schedule.channelName,
                scheduleId: schedule.id,
                ownerUserId: appVM.slackUserId,
                ownerDisplayName: appVM.slackUserDisplayName,
                userNames: appVM.userNameCache
            )

            // Move current draft to history and set new draft
            var updated = schedule
            if var lastSession = updated.sessions.last {
                let historyEntry = DraftEntry(
                    id: UUID(),
                    draft: session.draftReply ?? "",
                    timestamp: Date(),
                    rewritePrompt: rewritePrompt
                )
                lastSession.draftHistory.append(historyEntry)
                lastSession.summary = result.summary
                lastSession.draftReply = result.draftReply
                updated.sessions[updated.sessions.count - 1] = lastSession
            }
            scheduleStore.updateSchedule(updated)

            if sentToBackground {
                schedulerEngine.backgroundTasks.removeValue(forKey: schedule.id)
                if let session = updated.latestSession {
                    appVM.notificationService.notifySessionReady(schedule: updated, session: session)
                }
            } else {
                isPresented = false
            }
        } catch {
            if sentToBackground {
                schedulerEngine.backgroundTasks.removeValue(forKey: schedule.id)
            }
            self.error = error.localizedDescription
        }

        isRewriting = false
    }
}
