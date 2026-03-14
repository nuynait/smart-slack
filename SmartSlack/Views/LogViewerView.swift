import SwiftUI

struct LogViewerView: View {
    @EnvironmentObject var logService: LogService
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var filterLevel: LogLevel = .info
    @State private var filterScheduleId: UUID?

    private var filteredLogs: [LogEntry] {
        logService.logs.filter { entry in
            if entry.level < filterLevel { return false }
            if let scheduleId = filterScheduleId, entry.scheduleId != scheduleId { return false }
            return true
        }
    }

    private func scheduleName(for id: UUID) -> String {
        scheduleStore.schedules.first { $0.id == id }?.name ?? id.uuidString.prefix(8).description
    }

    /// Unique schedule IDs that have logs
    private var scheduleIdsWithLogs: [UUID] {
        Array(Set(logService.logs.map(\.scheduleId))).sorted {
            scheduleName(for: $0) < scheduleName(for: $1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Level", selection: $filterLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .frame(width: 150)

                Picker("Schedule", selection: $filterScheduleId) {
                    Text("All Schedules").tag(nil as UUID?)
                    ForEach(scheduleIdsWithLogs, id: \.self) { id in
                        Text(scheduleName(for: id)).tag(id as UUID?)
                    }
                }
                .frame(width: 200)

                Spacer()

                Button {
                    logService.loadAllLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload logs")

                if let scheduleId = filterScheduleId {
                    Button {
                        logService.clearLogs(for: scheduleId)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear logs for \(scheduleName(for: scheduleId))")
                } else {
                    Button {
                        logService.clearAllLogs()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear all logs")
                }
            }
            .padding(8)

            Divider()

            if filteredLogs.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text",
                    description: Text("No log entries match the current filters")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLogs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp.shortFormatted)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 140, alignment: .leading)

                                Text(entry.level.rawValue.uppercased())
                                    .font(.caption.monospaced().bold())
                                    .foregroundStyle(levelColor(entry.level))
                                    .frame(width: 60)

                                Text(scheduleName(for: entry.scheduleId))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.blue)
                                    .frame(width: 100, alignment: .leading)
                                    .lineLimit(1)

                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: 700, minHeight: 400)
        .onAppear {
            logService.loadAllLogs()
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .verbose: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
