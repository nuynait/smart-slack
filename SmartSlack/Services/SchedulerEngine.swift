import Foundation
import Combine

@MainActor
final class SchedulerEngine: ObservableObject {
    @Published var countdowns: [UUID: TimeInterval] = [:]
    @Published var runningSchedules: Set<UUID> = []

    private var timers: [UUID: Timer] = [:]
    private let scheduleStore: ScheduleStore
    private let logService: LogService
    private var slackService: SlackService?
    private var ownerUserId: String?
    private var ownerDisplayName: String?

    init(scheduleStore: ScheduleStore, logService: LogService) {
        self.scheduleStore = scheduleStore
        self.logService = logService
    }

    func setSlackService(_ service: SlackService) {
        self.slackService = service
    }

    func setOwner(userId: String?, displayName: String?) {
        self.ownerUserId = userId
        self.ownerDisplayName = displayName
    }

    // MARK: - Start / Stop

    func startSchedule(_ schedule: Schedule) {
        guard schedule.status == .active else { return }
        stopSchedule(schedule.id)

        countdowns[schedule.id] = 0
        logService.log(.info, scheduleId: schedule.id, message: "Started schedule '\(schedule.name)' with interval \(schedule.intervalSeconds)s")

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(schedule.id)
            }
        }
        timers[schedule.id] = timer
    }

    func stopSchedule(_ id: UUID) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        countdowns.removeValue(forKey: id)
        runningSchedules.remove(id)
    }

    func triggerManually(_ id: UUID) {
        guard let schedule = scheduleStore.schedule(byId: id) else { return }
        countdowns[id] = 0
        Task {
            await executeSchedule(schedule)
            if schedule.status == .active {
                countdowns[id] = TimeInterval(schedule.intervalSeconds)
            }
        }
    }

    func startAllActive() {
        for schedule in scheduleStore.schedules where schedule.status == .active {
            startSchedule(schedule)
        }
    }

    func stopAll() {
        for id in timers.keys {
            stopSchedule(id)
        }
    }

    // MARK: - Timer

    private func tick(_ id: UUID) {
        guard var remaining = countdowns[id] else { return }
        remaining -= 1

        if remaining <= 0 {
            countdowns[id] = 0
            guard let schedule = scheduleStore.schedule(byId: id), schedule.status == .active else { return }
            Task {
                await executeSchedule(schedule)
                // Reload in case it was updated
                if let updated = scheduleStore.schedule(byId: id), updated.status == .active {
                    countdowns[id] = TimeInterval(updated.intervalSeconds)
                }
            }
        } else {
            countdowns[id] = remaining
        }
    }

    // MARK: - Execution

    private func executeSchedule(_ schedule: Schedule) async {
        guard let slackService else {
            logService.log(.error, scheduleId: schedule.id, message: "No Slack service configured")
            return
        }

        guard !runningSchedules.contains(schedule.id) else {
            logService.log(.warning, scheduleId: schedule.id, message: "Schedule already running, skipping")
            return
        }

        runningSchedules.insert(schedule.id)
        let sessionId = UUID()
        logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Fetching new messages")

        do {
            // Fetch messages
            let messages: [SlackMessage]
            if schedule.type == .thread, let threadTs = schedule.threadTs {
                messages = try await slackService.conversationsReplies(
                    channelId: schedule.channelId,
                    ts: threadTs,
                    oldest: schedule.lastMessageTs
                )
            } else {
                messages = try await slackService.conversationsHistory(
                    channelId: schedule.channelId,
                    oldest: schedule.lastMessageTs
                )
            }

            // Filter out messages we've already seen
            let newMessages = schedule.lastMessageTs != nil
                ? messages.filter { msg in
                    guard let ts = msg.ts, let lastTs = schedule.lastMessageTs else { return true }
                    return ts > lastTs
                }
                : messages

            guard !newMessages.isEmpty else {
                logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "No new messages")
                runningSchedules.remove(schedule.id)
                var updated = schedule
                updated.lastRun = Date()
                scheduleStore.updateSchedule(updated)
                return
            }

            // Skip Claude if all new messages are from the owner, but store them
            if let ownerId = ownerUserId {
                let allFromOwner = newMessages.allSatisfy { $0.user == ownerId }
                if allFromOwner {
                    logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "All \(newMessages.count) new messages are from owner, storing without Claude")
                    runningSchedules.remove(schedule.id)
                    var updated = schedule
                    updated.lastRun = Date()
                    updated.lastMessageTs = newMessages.compactMap(\.ts).max() ?? schedule.lastMessageTs
                    updated.pendingMessages.append(contentsOf: newMessages)
                    scheduleStore.updateSchedule(updated)
                    return
                }
            }

            // Merge any pending owner messages with new messages for full context
            let allMessages = schedule.pendingMessages + newMessages

            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Found \(newMessages.count) new messages (\(schedule.pendingMessages.count) pending), calling Claude")

            // Download images from messages
            let imagePaths = await downloadImages(from: allMessages, scheduleId: schedule.id, sessionId: sessionId, slackService: slackService)
            if !imagePaths.isEmpty {
                logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Downloaded \(imagePaths.count) images")
            }

            // Call Claude
            let result = try await ClaudeService.analyze(
                messages: allMessages,
                prompt: schedule.prompt,
                channelName: schedule.channelName,
                ownerUserId: ownerUserId,
                ownerDisplayName: ownerDisplayName,
                imagePaths: imagePaths
            )

            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Claude prompt:\n\(result.promptSent)")
            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Claude response:\n\(result.rawResponse)")

            // Create session with all messages (pending + new)
            let session = Session(
                sessionId: sessionId,
                timestamp: Date(),
                messages: allMessages,
                summary: result.summary,
                draftReply: result.draftReply,
                draftHistory: [],
                finalAction: .pending,
                sentMessage: nil
            )

            // Update schedule, clear pending messages
            var updated = schedule
            updated.lastRun = Date()
            updated.lastMessageTs = newMessages.compactMap(\.ts).max() ?? schedule.lastMessageTs
            updated.pendingMessages = []
            updated.sessions.append(session)
            scheduleStore.updateSchedule(updated)

        } catch {
            logService.log(.error, scheduleId: schedule.id, sessionId: sessionId, message: "Error: \(error.localizedDescription)")
            var updated = schedule
            updated.status = .failed
            updated.lastRun = Date()
            scheduleStore.updateSchedule(updated)
            stopSchedule(schedule.id)
        }

        runningSchedules.remove(schedule.id)
    }

    // MARK: - Image Download

    private func downloadImages(from messages: [SlackMessage], scheduleId: UUID, sessionId: UUID, slackService: SlackService) async -> [String] {
        let imageFiles = messages.flatMap(\.imageFiles)
        guard !imageFiles.isEmpty else { return [] }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartSlack")
            .appendingPathComponent(sessionId.uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var paths: [String] = []
        for file in imageFiles {
            guard let url = file.bestUrl else { continue }
            let ext = file.filetype ?? "png"
            let fileName = "\(file.id).\(ext)"
            let dest = tempDir.appendingPathComponent(fileName)
            do {
                try await slackService.downloadFile(url: url, to: dest)
                paths.append(dest.path)
            } catch {
                logService.log(.warning, scheduleId: scheduleId, sessionId: sessionId, message: "Failed to download image \(file.name ?? file.id): \(error.localizedDescription)")
            }
        }
        return paths
    }
}
