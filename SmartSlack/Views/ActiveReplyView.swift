import SwiftUI

struct ActiveReplyView: View {
    let schedule: Schedule
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @Binding var isPresented: Bool
    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var error: String?
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isGenerating { isPresented = false }
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Active Reply", systemImage: "arrow.uturn.left.circle")
                        .font(.headline)
                    Spacer()
                    if !isGenerating {
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Draft a reply using Claude without waiting for new messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
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
                    .disabled(isGenerating)
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    if isGenerating {
                        Button {
                            schedulerEngine.runActiveReplyInBackground(
                                schedule: schedule,
                                prompt: prompt,
                                userNames: appVM.userNameCache
                            )
                            isPresented = false
                        } label: {
                            Label("Run in Background", systemImage: "arrow.down.app")
                        }
                        .buttonStyle(.secondary)
                    }

                    Button {
                        Task { await generateReply() }
                    } label: {
                        if isGenerating {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Generating...")
                            }
                        } else {
                            Label("Draft Reply", systemImage: "paperplane")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(prompt.isEmpty || isGenerating)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 480)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 5)
        }
        .onAppear {
            DispatchQueue.main.async { isPromptFocused = true }
        }
    }

    private func generateReply() async {
        isGenerating = true
        error = nil

        do {
            // Gather conversation messages from all sessions
            var seen = Set<String>()
            var allMessages: [SlackMessage] = []
            for session in schedule.sessions {
                for msg in session.messages {
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

            let result = try await ClaudeService.analyze(
                messages: allMessages,
                prompt: prompt,
                channelName: schedule.channelName,
                scheduleId: schedule.id,
                ownerUserId: appVM.slackUserId,
                ownerDisplayName: appVM.slackUserDisplayName,
                userNames: appVM.userNameCache
            )

            let session = Session(
                sessionId: UUID(),
                timestamp: Date(),
                messages: allMessages,
                summary: result.summary,
                draftReply: result.draftReply,
                draftHistory: [],
                finalAction: .pending,
                sentMessage: nil
            )

            var updated = schedule
            updated.lastRun = Date()
            updated.sessions.append(session)
            scheduleStore.updateSchedule(updated)

            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
    }
}
