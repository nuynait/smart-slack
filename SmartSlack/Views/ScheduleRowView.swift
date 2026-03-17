import SwiftUI

struct ScheduleRowView: View {
    let schedule: Schedule
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @AppStorage("showNotificationModeInSidebar") private var showNotificationMode = false

    private var countdown: TimeInterval? {
        schedulerEngine.countdowns[schedule.id]
    }

    private var isRunning: Bool {
        schedulerEngine.runningSchedules.contains(schedule.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: channelIcon)
                        .font(.caption2)
                    Text(schedule.channelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if showNotificationMode {
                Image(systemName: notificationIcon)
                    .foregroundStyle(notificationColor)
                    .font(.caption2)
                    .help(notificationLabel)
            }

            Spacer()

            if schedule.autoSend {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.blue)
                    .font(.caption2)
            }

            if schedule.hasUnresolvedDraft {
                Image(systemName: "envelope.badge.fill")
                    .foregroundStyle(Color.statusPending)
                    .font(.caption)
            }

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else if let countdown, schedule.status == .active {
                Text(countdown.countdownFormatted)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch schedule.status {
        case .active: return .statusActive
        case .completed: return .statusCompleted
        case .failed: return .statusFailed
        }
    }

    private var notificationIcon: String {
        switch schedule.notificationMode {
        case .macosNotification: return "bell.fill"
        case .forcePopup: return "exclamationmark.bubble.fill"
        case .quiet: return "bell.slash.fill"
        }
    }

    private var notificationColor: Color {
        switch schedule.notificationMode {
        case .macosNotification: return .blue
        case .forcePopup: return .orange
        case .quiet: return .secondary
        }
    }

    private var notificationLabel: String {
        switch schedule.notificationMode {
        case .macosNotification: return "Notification"
        case .forcePopup: return "Force Popup"
        case .quiet: return "Quiet"
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
}
