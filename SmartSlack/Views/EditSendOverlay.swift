import SwiftUI

struct EditSendOverlay: View {
    let schedule: Schedule
    let session: Session
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @Binding var isPresented: Bool
    @Binding var showSendTarget: Bool
    @Binding var sendTargetDraft: String
    @State private var draftText: String
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var isTextFocused: Bool

    init(schedule: Schedule, session: Session, isPresented: Binding<Bool>, showSendTarget: Binding<Bool>, sendTargetDraft: Binding<String>) {
        self.schedule = schedule
        self.session = session
        self._isPresented = isPresented
        self._showSendTarget = showSendTarget
        self._sendTargetDraft = sendTargetDraft
        self._draftText = State(initialValue: session.draftReply ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSending { isPresented = false }
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Edit & Send", systemImage: "pencil.line")
                        .font(.headline)
                    Spacer()
                    if !isSending {
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Edit the draft before sending.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $draftText)
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: 200)
                    .focused($isTextFocused)

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
                    .disabled(isSending)
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Sending...")
                            }
                        } else if schedule.type != .thread {
                            Label("Send to...", systemImage: "paperplane.fill")
                        } else {
                            Label("Send", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
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
            DispatchQueue.main.async { isTextFocused = true }
        }
    }

    private func send() async {
        if schedule.type != .thread {
            // Route through send target picker
            sendTargetDraft = draftText
            isPresented = false
            showSendTarget = true
            return
        }

        guard let slackService = appVM.slackService else { return }
        isSending = true
        error = nil

        do {
            _ = try await slackService.postMessage(
                channelId: schedule.channelId,
                text: draftText,
                threadTs: schedule.threadTs
            )

            var updated = schedule
            if var lastSession = updated.sessions.last {
                lastSession.finalAction = .sent
                lastSession.sentMessage = draftText
                updated.sessions[updated.sessions.count - 1] = lastSession
            }
            scheduleStore.updateSchedule(updated)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }

        isSending = false
    }
}
