import Foundation

enum ScheduleType: String, Codable, CaseIterable, Hashable {
    case channel
    case thread
    case dm
    case dmgroup
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

    var id: UUID { sessionId }
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

    var latestSession: Session? {
        sessions.last
    }
}
