import Foundation
import Combine

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var schedules: [Schedule] = []

    private let schedulersDir = Constants.schedulersDir
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init() {
        migrateIfNeeded()
        loadSchedules()
        startWatching()
    }

    deinit {
        source?.cancel()
        timer?.invalidate()
    }

    func loadSchedules() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: schedulersDir.path) else {
            schedules = []
            return
        }

        do {
            let subdirs = try fm.contentsOfDirectory(at: schedulersDir, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

            var loaded: [Schedule] = []
            for subdir in subdirs {
                let file = subdir.appendingPathComponent("schedule.json")
                guard fm.fileExists(atPath: file.path) else { continue }
                do {
                    let data = try Data(contentsOf: file)
                    let schedule = try JSONDecoder.slackDecoder.decode(Schedule.self, from: data)
                    loaded.append(schedule)
                } catch {
                    print("Warning: skipping corrupt schedule file \(file.path): \(error)")
                }
            }
            schedules = loaded.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("Failed to read schedulers directory: \(error)")
            schedules = []
        }
    }

    func saveSchedule(_ schedule: Schedule) {
        let file = Constants.scheduleFile(for: schedule.id)
        do {
            let data = try JSONEncoder.slackEncoder.encode(schedule)
            try data.write(to: file)
            loadSchedules()
        } catch {
            print("Failed to save schedule: \(error)")
        }
    }

    func updateSchedule(_ schedule: Schedule) {
        saveSchedule(schedule)
    }

    func deleteSchedule(_ schedule: Schedule) {
        // Remove the entire scheduler directory (schedule.json, memory.md, claude_output/)
        let dir = Constants.schedulerDir(for: schedule.id)
        try? FileManager.default.removeItem(at: dir)
        loadSchedules()
    }

    func schedule(byId id: UUID) -> Schedule? {
        schedules.first { $0.id == id }
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        let fm = FileManager.default
        let legacyDir = Constants.legacySchedulesDir

        guard fm.fileExists(atPath: legacyDir.path) else { return }

        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
        } catch {
            return
        }

        guard !files.isEmpty else {
            // Empty legacy dir, clean up
            try? fm.removeItem(at: legacyDir)
            return
        }

        print("[SmartSlack] Migrating \(files.count) schedules to new layout...")

        for file in files {
            let uuid = file.deletingPathExtension().lastPathComponent
            guard let scheduleId = UUID(uuidString: uuid) else { continue }

            let newDir = Constants.schedulerDir(for: scheduleId)
            let newFile = newDir.appendingPathComponent("schedule.json")

            // Move schedule JSON
            if !fm.fileExists(atPath: newFile.path) {
                do {
                    try fm.moveItem(at: file, to: newFile)
                } catch {
                    print("[SmartSlack] Failed to migrate schedule \(uuid): \(error)")
                    continue
                }
            }

            // Move claude_output if it exists
            let legacyOutput = Constants.legacyClaudeOutputDir.appendingPathComponent(uuid)
            let newOutput = newDir.appendingPathComponent("claude_output")
            if fm.fileExists(atPath: legacyOutput.path) && !fm.fileExists(atPath: newOutput.path) {
                try? fm.moveItem(at: legacyOutput, to: newOutput)
            }
        }

        // Clean up empty legacy directories
        if let remaining = try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil), remaining.isEmpty {
            try? fm.removeItem(at: legacyDir)
        }
        let legacyOutput = Constants.legacyClaudeOutputDir
        if fm.fileExists(atPath: legacyOutput.path),
           let remaining = try? fm.contentsOfDirectory(at: legacyOutput, includingPropertiesForKeys: nil), remaining.isEmpty {
            try? fm.removeItem(at: legacyOutput)
        }

        print("[SmartSlack] Migration complete")
    }

    // MARK: - File Watching

    private func startWatching() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: schedulersDir.path) {
            try? fm.createDirectory(at: schedulersDir, withIntermediateDirectories: true)
        }

        let fd = open(schedulersDir.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.loadSchedules()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            self.source = source
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadSchedules()
            }
        }
    }
}
