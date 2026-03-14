import Foundation

enum Constants {
    static let appSupportDir: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SmartSlack")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let schedulesDir: URL = {
        let url = appSupportDir.appendingPathComponent("schedules")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let claudeOutputDir: URL = {
        let url = appSupportDir.appendingPathComponent("claude_output")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let logsDir: URL = {
        let url = appSupportDir.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let keychainServiceName = "com.tshan.smartslack"
    static let keychainAccountName = "slack-token"

    static let claudePath = "/opt/homebrew/bin/claude"

    static let slackBaseURL = "https://slack.com/api"

    static let slackScopes = [
        "channels:history",
        "channels:read",
        "chat:write",
        "groups:history",
        "groups:read",
        "im:history",
        "im:read",
        "mpim:history",
        "mpim:read",
        "users:read",
        "search:read",
        "files:read",
    ]

    static let draftSignature = "\n\n— drafted with Claude Code"

    static let starredChannelsFile: URL = appSupportDir.appendingPathComponent("starred_channels.json")
    static let userColorsFile: URL = appSupportDir.appendingPathComponent("user_colors.json")
}
