import Foundation

actor SlackService {
    private let token: String
    private let session = URLSession.shared
    private let baseURL = Constants.slackBaseURL

    init(token: String) {
        self.token = token
    }

    // MARK: - Auth

    func authTest() async throws -> SlackAuthTestResponse {
        let data = try await post(endpoint: "auth.test")
        return try JSONDecoder.slackDecoder.decode(SlackAuthTestResponse.self, from: data)
    }

    // MARK: - Conversations

    func listConversations(types: String = "public_channel,private_channel,mpim,im") async throws -> [SlackChannel] {
        var allChannels: [SlackChannel] = []
        var cursor: String?

        repeat {
            var params: [(String, String)] = [
                ("types", types),
                ("limit", "200"),
                ("exclude_archived", "true"),
            ]
            if let cursor, !cursor.isEmpty {
                params.append(("cursor", cursor))
            }

            let data = try await get(endpoint: "conversations.list", params: params)
            let response = try JSONDecoder.slackDecoder.decode(SlackConversationsListResponse.self, from: data)

            guard response.ok else {
                throw SlackError.apiError(response.error ?? "Unknown error")
            }

            allChannels.append(contentsOf: response.channels ?? [])
            cursor = response.responseMetadata?.nextCursor
        } while cursor != nil && !cursor!.isEmpty

        return allChannels
    }

    func conversationsHistory(channelId: String, oldest: String? = nil, limit: Int = 100) async throws -> [SlackMessage] {
        var params: [(String, String)] = [
            ("channel", channelId),
            ("limit", "\(limit)"),
        ]
        if let oldest {
            params.append(("oldest", oldest))
        }

        let data = try await get(endpoint: "conversations.history", params: params)
        let response = try JSONDecoder.slackDecoder.decode(SlackConversationsHistoryResponse.self, from: data)

        guard response.ok else {
            throw SlackError.apiError(response.error ?? "Unknown error")
        }

        return response.messages ?? []
    }

    func conversationsReplies(channelId: String, ts: String, oldest: String? = nil) async throws -> [SlackMessage] {
        var params: [(String, String)] = [
            ("channel", channelId),
            ("ts", ts),
        ]
        if let oldest {
            params.append(("oldest", oldest))
        }

        let data = try await get(endpoint: "conversations.replies", params: params)
        let response = try JSONDecoder.slackDecoder.decode(SlackConversationsRepliesResponse.self, from: data)

        guard response.ok else {
            throw SlackError.apiError(response.error ?? "Unknown error")
        }

        return response.messages ?? []
    }

    func postMessage(channelId: String, text: String, threadTs: String? = nil) async throws -> SlackPostMessageResponse {
        var body: [String: String] = [
            "channel": channelId,
            "text": text + Constants.draftSignature,
        ]
        if let threadTs {
            body["thread_ts"] = threadTs
        }

        let data = try await post(endpoint: "chat.postMessage", jsonBody: body)
        let response = try JSONDecoder.slackDecoder.decode(SlackPostMessageResponse.self, from: data)

        guard response.ok else {
            throw SlackError.apiError(response.error ?? "Unknown error")
        }

        return response
    }

    func usersInfo(userId: String) async throws -> SlackUserInfo? {
        let data = try await get(endpoint: "users.info", params: [("user", userId)])
        let response = try JSONDecoder.slackDecoder.decode(SlackUsersInfoResponse.self, from: data)
        return response.user
    }

    // MARK: - HTTP

    private func get(endpoint: String, params: [(String, String)] = []) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        var request = URLRequest(url: components.url!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SlackError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func post(endpoint: String, jsonBody: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let jsonBody {
            request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        } else {
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SlackError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}

enum SlackError: LocalizedError {
    case apiError(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "Slack API: \(msg)"
        case .httpError(let code): return "HTTP \(code)"
        }
    }
}
