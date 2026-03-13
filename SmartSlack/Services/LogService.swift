import Foundation
import Combine

enum LogLevel: String, Codable, CaseIterable {
    case info
    case warning
    case error
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

    func loadLogs(scheduleId: UUID? = nil) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: logsDir.path) else { return }

        do {
            let files = try fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "log" }

            var allEntries: [LogEntry] = []
            for file in files {
                if let scheduleId, !file.lastPathComponent.hasPrefix(scheduleId.uuidString) {
                    continue
                }
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
                    for line in lines {
                        if let data = line.data(using: .utf8),
                           let entry = try? JSONDecoder.slackDecoder.decode(LogEntry.self, from: data) {
                            allEntries.append(entry)
                        }
                    }
                }
            }
            logs = allEntries.sorted { $0.timestamp < $1.timestamp }
        } catch {
            print("Failed to load logs: \(error)")
        }
    }

    private func writeToFile(_ entry: LogEntry) {
        let sessionSuffix = entry.sessionId?.uuidString ?? "general"
        let filename = "\(entry.scheduleId.uuidString)_\(sessionSuffix).log"
        let file = logsDir.appendingPathComponent(filename)

        do {
            let data = try JSONEncoder.slackEncoder.encode(entry)
            let line = String(data: data, encoding: .utf8)! + "\n"

            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try line.write(to: file, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to write log: \(error)")
        }
    }
}
