import SwiftUI

struct ScheduleDetailView: View {
    let schedule: Schedule
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @State private var showEditSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()

                if let session = schedule.latestSession {
                    sessionSection(session)
                } else {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock",
                        description: Text("Waiting for the next scheduled check")
                    )
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if schedule.status == .active {
                    Button {
                        schedulerEngine.triggerManually(schedule.id)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Trigger now")

                    Button {
                        var updated = schedule
                        updated.status = .completed
                        scheduleStore.updateSchedule(updated)
                        schedulerEngine.stopSchedule(schedule.id)
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .help("Mark as completed")
                }

                if schedule.status == .failed {
                    Button {
                        var updated = schedule
                        updated.status = .active
                        scheduleStore.updateSchedule(updated)
                        schedulerEngine.startSchedule(updated)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Restart schedule")
                }

                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit schedule")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditScheduleView(schedule: schedule)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(schedule.name)
                    .font(.title2.bold())

                statusPill
            }

            HStack(spacing: 16) {
                Label(schedule.channelName, systemImage: channelIcon)
                    .font(.subheadline)

                Label("Every \(formatInterval(schedule.intervalSeconds))", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let lastRun = schedule.lastRun {
                    Label("Last run: \(lastRun.relativeFormatted)", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !schedule.prompt.isEmpty {
                Text(schedule.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.quaternary)
                    .cornerRadius(6)
            }
        }
    }

    private var statusPill: some View {
        Text(schedule.status.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.2))
            .foregroundStyle(pillColor)
            .clipShape(Capsule())
    }

    private var pillColor: Color {
        switch schedule.status {
        case .active: return .statusActive
        case .completed: return .statusCompleted
        case .failed: return .statusFailed
        }
    }

    private var channelIcon: String {
        switch schedule.type {
        case .channel: return "number"
        case .thread: return "bubble.left.and.bubble.right"
        case .dm: return "person"
        case .dmgroup: return "person.3"
        }
    }

    // MARK: - Session

    private func sessionSection(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Messages
            if !session.messages.isEmpty {
                sectionHeader("Conversation", icon: "bubble.left.and.bubble.right")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(session.messages) { message in
                        HStack(alignment: .top, spacing: 8) {
                            Text(message.user ?? "?")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                                .frame(width: 80, alignment: .trailing)
                            Text(message.text ?? "")
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
                .background(.quaternary)
                .cornerRadius(8)
            }

            // Summary
            if let summary = session.summary {
                sectionHeader("Summary", icon: "text.alignleft")
                Text(summary)
                    .padding(12)
                    .background(.quaternary)
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }

            // Draft
            if session.finalAction == .pending {
                DraftView(schedule: schedule, session: session)
            } else {
                completedActionView(session)
            }

            // History
            if !session.draftHistory.isEmpty {
                DraftHistoryView(schedule: schedule, session: session)
            }
        }
    }

    private func completedActionView(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                session.finalAction == .sent ? "Sent" : "Ignored",
                icon: session.finalAction == .sent ? "paperplane.fill" : "xmark.circle"
            )

            if let sent = session.sentMessage {
                Text(sent)
                    .padding(12)
                    .background(.green.opacity(0.1))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func formatInterval(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        if remaining == 0 { return "\(minutes)m" }
        return "\(minutes)m \(remaining)s"
    }
}
