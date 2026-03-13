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

    init(scheduleStore: ScheduleStore, logService: LogService) {
        self.scheduleStore = scheduleStore
        self.logService = logService
    }

    func setSlackService(_ service: SlackService) {
        self.slackService = service
    }

    // MARK: - Start / Stop

    func startSchedule(_ schedule: Schedule) {
        guard schedule.status == .active else { return }
        stopSchedule(schedule.id)

        countdowns[schedule.id] = TimeInterval(schedule.intervalSeconds)
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

            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Found \(newMessages.count) new messages, calling Claude")

            // Call Claude
            let result = try await ClaudeService.analyze(
                messages: newMessages,
                prompt: schedule.prompt,
                channelName: schedule.channelName
            )

            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Claude analysis complete")

            // Create session
            let session = Session(
                sessionId: sessionId,
                timestamp: Date(),
                messages: newMessages,
                summary: result.summary,
                draftReply: result.draftReply,
                draftHistory: [],
                finalAction: .pending,
                sentMessage: nil
            )

            // Update schedule
            var updated = schedule
            updated.lastRun = Date()
            updated.lastMessageTs = newMessages.compactMap(\.ts).max() ?? schedule.lastMessageTs
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
}
