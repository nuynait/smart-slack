import Foundation
import Combine

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var schedules: [Schedule] = []

    private let schedulesDir = Constants.schedulesDir
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init() {
        loadSchedules()
        startWatching()
    }

    deinit {
        source?.cancel()
        timer?.invalidate()
    }

    func loadSchedules() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: schedulesDir.path) else {
            schedules = []
            return
        }

        do {
            let files = try fm.contentsOfDirectory(at: schedulesDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }

            var loaded: [Schedule] = []
            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    let schedule = try JSONDecoder.slackDecoder.decode(Schedule.self, from: data)
                    loaded.append(schedule)
                } catch {
                    print("Warning: skipping corrupt schedule file \(file.lastPathComponent): \(error)")
                }
            }
            schedules = loaded.sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("Failed to read schedules directory: \(error)")
            schedules = []
        }
    }

    func saveSchedule(_ schedule: Schedule) {
        let file = schedulesDir.appendingPathComponent("\(schedule.id.uuidString).json")
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
        let file = schedulesDir.appendingPathComponent("\(schedule.id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
        loadSchedules()
    }

    func schedule(byId id: UUID) -> Schedule? {
        schedules.first { $0.id == id }
    }

    // MARK: - File Watching

    private func startWatching() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: schedulesDir.path) {
            try? fm.createDirectory(at: schedulesDir, withIntermediateDirectories: true)
        }

        let fd = open(schedulesDir.path, O_EVTONLY)
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
