import Foundation
import Combine

enum BackgroundTaskType: String {
    case rewrite = "Rewriting draft..."
    case activeReply = "Generating reply..."
}

struct BackgroundTaskInfo: Identifiable {
    let id = UUID()
    let scheduleId: UUID
    let type: BackgroundTaskType
}

@MainActor
final class SchedulerEngine: ObservableObject {
    @Published var countdowns: [UUID: TimeInterval] = [:]
    @Published var runningSchedules: Set<UUID> = []
    @Published var autoSendCountdowns: [UUID: Int] = [:]
    @Published var backgroundTasks: [UUID: BackgroundTaskInfo] = [:]
    private(set) var skippedTicks: Set<UUID> = []

    private var timers: [UUID: Timer] = [:]
    private var autoSendTimers: [UUID: Timer] = [:]
    private let scheduleStore: ScheduleStore
    private let logService: LogService
    private var slackService: SlackService?
    private var ownerUserId: String?
    private var ownerDisplayName: String?
    private var userNameResolver: (() -> [String: String])?
    private var userNameUpdater: (([String: String]) -> Void)?
    private var notificationService: NotificationService?

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

    func setUserNameResolver(_ resolver: @escaping () -> [String: String], updater: @escaping ([String: String]) -> Void) {
        self.userNameResolver = resolver
        self.userNameUpdater = updater
    }

    func setNotificationService(_ service: NotificationService) {
        self.notificationService = service
    }

    // MARK: - Start / Stop

    func startSchedule(_ schedule: Schedule) {
        guard schedule.status == .active else { return }
        stopSchedule(schedule.id)

        // interval 0 = manual only, no timer
        guard schedule.intervalSeconds > 0 else {
            logService.log(.info, scheduleId: schedule.id, message: "Started schedule '\(schedule.name)' in manual mode (no automatic checks)")
            return
        }

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
        guard !runningSchedules.contains(id) else {
            logService.log(.warning, scheduleId: id, message: "Manual trigger skipped — schedule already running")
            return
        }
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

    // MARK: - Draft Resolution

    /// Call after resolving a draft (send/ignore). If ticks were skipped while the draft was pending,
    /// immediately triggers a new execution to catch up on missed messages.
    func onDraftResolved(for scheduleId: UUID) {
        guard skippedTicks.remove(scheduleId) != nil else { return }
        guard let schedule = scheduleStore.schedule(byId: scheduleId),
              schedule.status == .active else { return }

        logService.log(.info, scheduleId: scheduleId, message: "Draft resolved — triggering catch-up execution for skipped ticks")
        Task {
            await executeSchedule(schedule)
            if let updated = scheduleStore.schedule(byId: scheduleId), updated.status == .active {
                countdowns[scheduleId] = TimeInterval(updated.intervalSeconds)
            }
        }
    }

    // MARK: - Auto-send

    func startAutoSend(for scheduleId: UUID) {
        cancelAutoSend(for: scheduleId)
        autoSendCountdowns[scheduleId] = 10
        autoSendTimers[scheduleId] = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard var remaining = self.autoSendCountdowns[scheduleId] else { return }
                remaining -= 1
                if remaining <= 0 {
                    self.cancelAutoSend(for: scheduleId)
                    await self.performAutoSend(for: scheduleId)
                } else {
                    self.autoSendCountdowns[scheduleId] = remaining
                }
            }
        }
    }

    func cancelAutoSend(for scheduleId: UUID) {
        autoSendTimers[scheduleId]?.invalidate()
        autoSendTimers.removeValue(forKey: scheduleId)
        autoSendCountdowns.removeValue(forKey: scheduleId)
    }

    func manualSendAutoSchedule(for scheduleId: UUID) async {
        cancelAutoSend(for: scheduleId)
        await performAutoSend(for: scheduleId)
    }

    private func performAutoSend(for scheduleId: UUID) async {
        guard let slackService,
              let schedule = scheduleStore.schedule(byId: scheduleId),
              let session = schedule.latestSession,
              session.finalAction == .pending,
              let draft = session.draftReply else { return }

        do {
            let threadTs = schedule.type == .thread ? schedule.threadTs : nil
            _ = try await slackService.postMessage(
                channelId: schedule.channelId,
                text: draft,
                threadTs: threadTs,
                appendSignature: schedule.signDrafts
            )

            var updated = schedule
            if var lastSession = updated.sessions.last {
                lastSession.finalAction = .sent
                lastSession.sentMessage = draft
                updated.sessions[updated.sessions.count - 1] = lastSession
            }
            scheduleStore.updateSchedule(updated)
            notificationService?.dequeueCurrentPopup()
            onDraftResolved(for: scheduleId)
        } catch {
            logService.log(.error, scheduleId: scheduleId, message: "Auto-send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer

    private func tick(_ id: UUID) {
        guard var remaining = countdowns[id] else { return }

        // Freeze countdown while schedule is executing
        if runningSchedules.contains(id) { return }

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

        // Skip tick if draft is pending or background task is running
        let currentSchedule = scheduleStore.schedule(byId: schedule.id) ?? schedule
        if currentSchedule.hasUnresolvedDraft || backgroundTasks[schedule.id] != nil {
            skippedTicks.insert(schedule.id)
            logService.log(.info, scheduleId: schedule.id, message: "Skipping tick — draft pending or background task running")
            return
        }

        runningSchedules.insert(schedule.id)
        let sessionId = UUID()
        logService.log(.verbose, scheduleId: schedule.id, sessionId: sessionId, message: "Fetching new messages")

        do {
            // Fetch messages
            let isFirstFetch = schedule.lastMessageTs == nil
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
            var newMessages = schedule.lastMessageTs != nil
                ? messages.filter { msg in
                    guard let ts = msg.ts, let lastTs = schedule.lastMessageTs else { return true }
                    return ts > lastTs
                }
                : messages

            // On first fetch, limit to initialMessageCount most recent messages.
            // Subsequent fetches use lastMessageTs so they only get new messages.
            if isFirstFetch && newMessages.count > schedule.initialMessageCount {
                newMessages = Array(newMessages.prefix(schedule.initialMessageCount))
            }

            if newMessages.isEmpty && !schedule.alwaysRun {
                logService.log(.verbose, scheduleId: schedule.id, sessionId: sessionId, message: "No new messages")
                runningSchedules.remove(schedule.id)
                var updated = scheduleStore.schedule(byId: schedule.id) ?? schedule
                updated.lastRun = Date()
                scheduleStore.updateSchedule(updated)
                return
            }

            if newMessages.isEmpty && schedule.alwaysRun {
                logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "No new messages but alwaysRun enabled — proceeding with last session messages")
                // Use messages from the latest session as context for Claude
                if let lastSession = schedule.latestSession {
                    newMessages = lastSession.messages
                }
            }

            // Skip Claude if all new messages are from the owner
            if let ownerId = ownerUserId {
                let allFromOwner = newMessages.allSatisfy { $0.user == ownerId }
                if allFromOwner {
                    logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "All \(newMessages.count) new messages are from owner, skipping Claude")
                    runningSchedules.remove(schedule.id)

                    let allMessages = schedule.pendingMessages + newMessages
                    let ownerSession = Session(
                        sessionId: sessionId,
                        timestamp: Date(),
                        messages: allMessages,
                        summary: "All \(newMessages.count) new message\(newMessages.count == 1 ? "" : "s") from you. No response needed.",
                        draftReply: nil,
                        draftHistory: [],
                        finalAction: .skipped,
                        sentMessage: nil,
                        skipReason: "All new messages are from you — skipped without calling Claude."
                    )

                    var updated = scheduleStore.schedule(byId: schedule.id) ?? schedule
                    updated.lastRun = Date()
                    updated.lastMessageTs = newMessages.compactMap(\.ts).max() ?? schedule.lastMessageTs
                    updated.pendingMessages = []
                    updated.sessions.append(ownerSession)
                    scheduleStore.updateSchedule(updated)
                    return
                }
            }

            // Merge any pending owner messages with new messages for full context
            let allMessages = schedule.pendingMessages + newMessages

            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Found \(newMessages.count) new messages (\(schedule.pendingMessages.count) pending), calling Claude")

            // Resolve all user names before calling Claude
            let userNames = await resolveUserNames(from: allMessages, slackService: slackService)

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
                scheduleId: schedule.id,
                hasFilter: schedule.filterSummary != nil,
                ownerUserId: ownerUserId,
                ownerDisplayName: ownerDisplayName,
                imagePaths: imagePaths,
                userNames: userNames
            )

            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Claude prompt:\n\(result.promptSent)")
            logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Claude response:\n\(result.rawResponse)")

            // Create session with all messages (pending + new)
            let session = Session(
                sessionId: sessionId,
                timestamp: Date(),
                messages: allMessages,
                summary: result.summary,
                draftReply: result.skipped ? nil : result.draftReply,
                draftHistory: [],
                finalAction: result.skipped ? .skipped : .pending,
                sentMessage: nil,
                skipReason: result.skipped ? result.draftReply : nil,
                memoryReport: result.memoryReport
            )

            // Update schedule, clear pending messages
            // Re-read from store to avoid overwriting fields updated concurrently (e.g. filterSummary)
            var updated = scheduleStore.schedule(byId: schedule.id) ?? schedule
            updated.lastRun = Date()
            updated.lastMessageTs = newMessages.compactMap(\.ts).max() ?? schedule.lastMessageTs
            updated.pendingMessages = []
            updated.sessions.append(session)
            scheduleStore.updateSchedule(updated)

            // Start auto-send countdown if enabled and not skipped
            if !result.skipped && updated.autoSend {
                startAutoSend(for: schedule.id)
            }

            // Notify based on skip status
            if !result.skipped {
                notificationService?.notifySessionReady(schedule: updated, session: session)
            } else {
                logService.log(.info, scheduleId: schedule.id, sessionId: sessionId, message: "Claude decided to skip: \(result.draftReply)")
                notificationService?.notifySkippedSession(schedule: updated, session: session)
            }

        } catch {
            logService.log(.error, scheduleId: schedule.id, sessionId: sessionId, message: "Error: \(error.localizedDescription)")
            var updated = scheduleStore.schedule(byId: schedule.id) ?? schedule
            updated.status = .failed
            updated.lastRun = Date()
            updated.failureReason = error.localizedDescription
            scheduleStore.updateSchedule(updated)
            stopSchedule(schedule.id)
        }

        runningSchedules.remove(schedule.id)
    }

    // MARK: - User Name Resolution

    private func resolveUserNames(from messages: [SlackMessage], slackService: SlackService) async -> [String: String] {
        var names = userNameResolver?() ?? [:]

        // Collect all user IDs: message authors + mentioned users
        var userIds = Set(messages.compactMap(\.user))
        let mentionPattern = /<@(U[A-Z0-9]+)>/
        for msg in messages {
            guard let text = msg.text else { continue }
            for match in text.matches(of: mentionPattern) {
                userIds.insert(String(match.1))
            }
        }

        // Resolve any IDs not already cached
        let unknown = userIds.filter { names[$0] == nil }
        for userId in unknown {
            if let info = try? await slackService.usersInfo(userId: userId) {
                let name = info.profile?.displayName.flatMap({ $0.isEmpty ? nil : $0 })
                    ?? info.profile?.realName.flatMap({ $0.isEmpty ? nil : $0 })
                    ?? info.realName
                    ?? info.name
                    ?? userId
                names[userId] = name
            }
        }

        // Push newly resolved names back to the shared cache
        if !unknown.isEmpty {
            userNameUpdater?(names)
        }

        return names
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

    // MARK: - Background Tasks (state only, work runs in the overlay's existing Task)
}
