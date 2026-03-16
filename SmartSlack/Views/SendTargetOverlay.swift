import SwiftUI

struct SendTargetOverlay: View {
    let schedule: Schedule
    let draftText: String
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @Binding var isPresented: Bool
    @State private var isSending = false
    @State private var error: String?

    private var recentMessages: [SlackMessage] {
        var seen = Set<String>()
        var all: [SlackMessage] = []
        for session in schedule.sessions {
            for msg in session.messages {
                let key = msg.ts ?? UUID().uuidString
                if !seen.contains(key) {
                    seen.insert(key)
                    all.append(msg)
                }
            }
        }
        for msg in schedule.pendingMessages {
            let key = msg.ts ?? UUID().uuidString
            if !seen.contains(key) {
                seen.insert(key)
                all.append(msg)
            }
        }
        // Sort newest first, take recent 8
        return all.sorted { ($0.ts ?? "") > ($1.ts ?? "") }
            .prefix(8)
            .map { $0 }
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
                    Label("Where to send?", systemImage: "paperplane")
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

                // Draft preview
                Text(draftText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.05))
                    .cornerRadius(6)

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                // Send to channel option
                Button {
                    Task { await send(threadTs: nil) }
                } label: {
                    HStack {
                        Image(systemName: channelIcon)
                        Text("Send to \(schedule.channelName)")
                            .fontWeight(.medium)
                        Spacer()
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isSending)

                // Thread options
                if !recentMessages.isEmpty {
                    Text("Or reply in a thread:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(recentMessages, id: \.id) { message in
                                threadOptionRow(message: message)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }

                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.secondary)
                .disabled(isSending)
                .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            .frame(width: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 5)
        }
    }

    private func threadOptionRow(message: SlackMessage) -> some View {
        let userId = message.user ?? "?"
        let displayName = appVM.displayName(for: userId)
        let preview = (message.text ?? "").prefix(80)
        let dateStr = slackTsToDate(message.ts).map {
            Self.timestampFormatter.string(from: $0)
        } ?? ""

        return Button {
            Task { await send(threadTs: message.ts) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.caption.bold())
                        Text(dateStr)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .padding(8)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }

    private var channelIcon: String {
        switch schedule.type {
        case .channel: return "number"
        case .thread: return "bubble.left.and.bubble.right"
        case .dm: return "person"
        case .dmgroup: return "person.3"
        }
    }

    private func send(threadTs: String?) async {
        guard let slackService = appVM.slackService else { return }
        isSending = true
        error = nil

        do {
            _ = try await slackService.postMessage(
                channelId: schedule.channelId,
                text: draftText,
                threadTs: threadTs
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

    private func slackTsToDate(_ ts: String?) -> Date? {
        guard let ts, let interval = Double(ts.split(separator: ".").first ?? "") else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
