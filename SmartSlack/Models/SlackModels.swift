import Foundation

struct SlackChannel: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let isChannel: Bool?
    let isGroup: Bool?
    let isIm: Bool?
    let isMpim: Bool?
    let user: String?

    var displayName: String {
        name ?? user ?? id
    }
}

struct SlackMessage: Codable, Identifiable, Hashable {
    let type: String?
    let user: String?
    let text: String?
    let ts: String?
    let threadTs: String?
    let replyCount: Int?

    var id: String { ts ?? UUID().uuidString }
}

struct SlackConversationsListResponse: Codable {
    let ok: Bool
    let channels: [SlackChannel]?
    let error: String?
    let responseMetadata: ResponseMetadata?
}

struct ResponseMetadata: Codable {
    let nextCursor: String?
}

struct SlackConversationsHistoryResponse: Codable {
    let ok: Bool
    let messages: [SlackMessage]?
    let hasMore: Bool?
    let error: String?
}

struct SlackConversationsRepliesResponse: Codable {
    let ok: Bool
    let messages: [SlackMessage]?
    let hasMore: Bool?
    let error: String?
}

struct SlackPostMessageResponse: Codable {
    let ok: Bool
    let ts: String?
    let error: String?
}

struct SlackAuthTestResponse: Codable {
    let ok: Bool
    let url: String?
    let team: String?
    let user: String?
    let teamId: String?
    let userId: String?
    let error: String?
}

struct SlackUsersInfoResponse: Codable {
    let ok: Bool
    let user: SlackUserInfo?
    let error: String?
}

struct SlackUserInfo: Codable {
    let id: String
    let name: String?
    let realName: String?
    let profile: SlackProfile?
}

struct SlackProfile: Codable {
    let displayName: String?
    let realName: String?
}
