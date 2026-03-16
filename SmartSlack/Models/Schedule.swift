import Foundation

enum ScheduleType: String, Codable, CaseIterable, Hashable {
    case channel
    case thread
    case dm
    case dmgroup
}

enum NotificationMode: String, Codable, CaseIterable, Hashable {
    case macosNotification
    case forcePopup
    case quiet
}

enum ScheduleStatus: String, Codable, Hashable {
    case active
    case completed
    case failed
}

enum FinalAction: String, Codable, Hashable {
    case sent
    case ignored
    case pending
    case skipped
}

struct DraftEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var draft: String
    var timestamp: Date
    var rewritePrompt: String?
}

struct Session: Codable, Identifiable, Hashable {
    var sessionId: UUID
    var timestamp: Date
    var messages: [SlackMessage]
    var summary: String?
    var draftReply: String?
    var draftHistory: [DraftEntry]
    var finalAction: FinalAction
    var sentMessage: String?
    var skipReason: String?

    var id: UUID { sessionId }

    init(sessionId: UUID, timestamp: Date, messages: [SlackMessage], summary: String?, draftReply: String?, draftHistory: [DraftEntry], finalAction: FinalAction, sentMessage: String?, skipReason: String? = nil) {
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.messages = messages
        self.summary = summary
        self.draftReply = draftReply
        self.draftHistory = draftHistory
        self.finalAction = finalAction
        self.sentMessage = sentMessage
        self.skipReason = skipReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        messages = try container.decode([SlackMessage].self, forKey: .messages)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        draftReply = try container.decodeIfPresent(String.self, forKey: .draftReply)
        draftHistory = try container.decode([DraftEntry].self, forKey: .draftHistory)
        finalAction = try container.decode(FinalAction.self, forKey: .finalAction)
        sentMessage = try container.decodeIfPresent(String.self, forKey: .sentMessage)
        skipReason = try container.decodeIfPresent(String.self, forKey: .skipReason)
    }
}

struct Schedule: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var type: ScheduleType
    var channelId: String
    var threadTs: String?
    var channelName: String
    var prompt: String
    var intervalSeconds: Int
    var status: ScheduleStatus
    var createdAt: Date
    var lastRun: Date?
    var lastMessageTs: String?
    var sessions: [Session]
    var pendingMessages: [SlackMessage]
    var initialMessageCount: Int
    var notificationMode: NotificationMode
    var skipNotificationMode: NotificationMode

    /// Latest session that was processed by Claude (has a summary).
    var latestSession: Session? {
        sessions.last(where: { $0.summary != nil })
    }

    /// Whether the latest session has an unresolved draft (pending action).
    var hasUnresolvedDraft: Bool {
        guard let latest = latestSession else { return false }
        return latest.finalAction == .pending
    }

    init(id: UUID, name: String, type: ScheduleType, channelId: String, threadTs: String?, channelName: String, prompt: String, intervalSeconds: Int, status: ScheduleStatus, createdAt: Date, lastRun: Date?, lastMessageTs: String?, sessions: [Session], pendingMessages: [SlackMessage] = [], initialMessageCount: Int = 5, notificationMode: NotificationMode = .macosNotification, skipNotificationMode: NotificationMode = .quiet) {
        self.id = id
        self.name = name
        self.type = type
        self.channelId = channelId
        self.threadTs = threadTs
        self.channelName = channelName
        self.prompt = prompt
        self.intervalSeconds = intervalSeconds
        self.status = status
        self.createdAt = createdAt
        self.lastRun = lastRun
        self.lastMessageTs = lastMessageTs
        self.sessions = sessions
        self.pendingMessages = pendingMessages
        self.initialMessageCount = initialMessageCount
        self.notificationMode = notificationMode
        self.skipNotificationMode = skipNotificationMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ScheduleType.self, forKey: .type)
        channelId = try container.decode(String.self, forKey: .channelId)
        threadTs = try container.decodeIfPresent(String.self, forKey: .threadTs)
        channelName = try container.decode(String.self, forKey: .channelName)
        prompt = try container.decode(String.self, forKey: .prompt)
        intervalSeconds = try container.decode(Int.self, forKey: .intervalSeconds)
        status = try container.decode(ScheduleStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastRun = try container.decodeIfPresent(Date.self, forKey: .lastRun)
        lastMessageTs = try container.decodeIfPresent(String.self, forKey: .lastMessageTs)
        sessions = try container.decode([Session].self, forKey: .sessions)
        pendingMessages = try container.decodeIfPresent([SlackMessage].self, forKey: .pendingMessages) ?? []
        initialMessageCount = try container.decodeIfPresent(Int.self, forKey: .initialMessageCount) ?? 5
        notificationMode = try container.decodeIfPresent(NotificationMode.self, forKey: .notificationMode) ?? .macosNotification
        skipNotificationMode = try container.decodeIfPresent(NotificationMode.self, forKey: .skipNotificationMode) ?? .quiet
    }
}
