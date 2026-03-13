import SwiftUI

struct ScheduleRowView: View {
    let schedule: Schedule
    @EnvironmentObject var schedulerEngine: SchedulerEngine

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

            Spacer()

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

    private var channelIcon: String {
        switch schedule.type {
        case .channel: return "number"
        case .thread: return "bubble.left.and.bubble.right"
        case .dm: return "person"
        case .dmgroup: return "person.3"
        }
    }
}
