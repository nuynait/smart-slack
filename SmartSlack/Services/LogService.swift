import Foundation
import Combine

enum LogLevel: String, Codable, CaseIterable, Comparable {
    case verbose
    case info
    case warning
    case error

    private var sortOrder: Int {
        switch self {
        case .verbose: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let scheduleId: UUID
    let sessionId: UUID?
    let level: LogLevel
    let message: String
}

@MainActor
final class LogService: ObservableObject {
    @Published var logs: [LogEntry] = []

    private let logsDir = Constants.logsDir

    /// Max size per log file (1 MB)
    static let maxLogFileSize: UInt64 = 1_024 * 1_024

    init() {
        loadAllLogs()
    }

    func log(_ level: LogLevel, scheduleId: UUID, sessionId: UUID? = nil, message: String) {
        let entry = LogEntry(
            id: UUID(),
            timestamp: Date(),
            scheduleId: scheduleId,
            sessionId: sessionId,
            level: level,
            message: message
        )
        logs.append(entry)
        writeToFile(entry)
    }

    func loadAllLogs() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: logsDir.path) else { return }

        do {
            let files = try fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "log" }

            var allEntries: [LogEntry] = []
            for file in files {
                allEntries.append(contentsOf: readLogFile(file))
            }
            logs = allEntries.sorted { $0.timestamp < $1.timestamp }
        } catch {
            print("Failed to load logs: \(error)")
        }
    }

    func loadLogs(scheduleId: UUID? = nil) {
        if let scheduleId {
            let file = logFile(for: scheduleId)
            let entries = readLogFile(file)
            // Merge: remove old entries for this schedule, add fresh ones
            logs.removeAll { $0.scheduleId == scheduleId }
            logs.append(contentsOf: entries)
            logs.sort { $0.timestamp < $1.timestamp }
        } else {
            loadAllLogs()
        }
    }

    func clearLogs(for scheduleId: UUID) {
        let file = logFile(for: scheduleId)
        try? FileManager.default.removeItem(at: file)
        logs.removeAll { $0.scheduleId == scheduleId }
    }

    func clearAllLogs() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "log" {
                try? fm.removeItem(at: file)
            }
        }
        logs.removeAll()
    }

    func deleteLogsForSchedule(_ scheduleId: UUID) {
        let file = logFile(for: scheduleId)
        try? FileManager.default.removeItem(at: file)
        logs.removeAll { $0.scheduleId == scheduleId }
    }

    // MARK: - Private

    private func logFile(for scheduleId: UUID) -> URL {
        logsDir.appendingPathComponent("\(scheduleId.uuidString).log")
    }

    private func readLogFile(_ file: URL) -> [LogEntry] {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        var entries: [LogEntry] = []
        for line in lines {
            if let data = line.data(using: .utf8),
               let entry = try? JSONDecoder.slackDecoder.decode(LogEntry.self, from: data) {
                entries.append(entry)
            }
        }
        return entries
    }

    private func writeToFile(_ entry: LogEntry) {
        let file = logFile(for: entry.scheduleId)

        do {
            let data = try JSONEncoder.slackEncoder.encode(entry)
            let line = String(data: data, encoding: .utf8)! + "\n"
            let fm = FileManager.default

            if fm.fileExists(atPath: file.path) {
                // Check file size and truncate if needed
                if let attrs = try? fm.attributesOfItem(atPath: file.path),
                   let fileSize = attrs[.size] as? UInt64,
                   fileSize > Self.maxLogFileSize {
                    truncateLogFile(file)
                }
                let handle = try FileHandle(forWritingTo: file)
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
                try line.write(to: file, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to write log: \(error)")
        }
    }

    /// Keep the newest half of log entries when file exceeds max size.
    private func truncateLogFile(_ file: URL) {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let keepCount = lines.count / 2
        let kept = Array(lines.suffix(keepCount))
        let newContent = kept.joined(separator: "\n") + "\n"
        try? newContent.write(to: file, atomically: true, encoding: .utf8)
    }
}
