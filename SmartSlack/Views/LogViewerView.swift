import SwiftUI

struct LogViewerView: View {
    @EnvironmentObject var logService: LogService
    @State private var filterLevel: LogLevel?
    @State private var filterScheduleId = ""

    private var filteredLogs: [LogEntry] {
        logService.logs.filter { entry in
            if let level = filterLevel, entry.level != level { return false }
            if !filterScheduleId.isEmpty,
               !entry.scheduleId.uuidString.lowercased().hasPrefix(filterScheduleId.lowercased()) {
                return false
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Level", selection: $filterLevel) {
                    Text("All").tag(nil as LogLevel?)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level as LogLevel?)
                    }
                }
                .frame(width: 150)

                TextField("Schedule ID filter...", text: $filterScheduleId)
                    .textFieldStyle(.roundedBorder)

                Button {
                    logService.loadLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding(8)

            Divider()

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
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            logService.loadLogs()
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
