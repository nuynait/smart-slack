import Foundation

enum MemoryStore {
    static func read(for scheduleId: UUID) -> String? {
        let file = Constants.memoryFile(for: scheduleId)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }

    static func write(_ content: String, for scheduleId: UUID) {
        let file = Constants.memoryFile(for: scheduleId)
        _ = Constants.schedulerDir(for: scheduleId)
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    static func delete(for scheduleId: UUID) {
        let file = Constants.memoryFile(for: scheduleId)
        try? FileManager.default.removeItem(at: file)
    }
}
