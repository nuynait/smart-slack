import Foundation

enum Constants {
    static let appSupportDir: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SmartSlack")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let schedulersDir: URL = {
        let url = appSupportDir.appendingPathComponent("schedulers")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // Legacy paths for migration
    static let legacySchedulesDir: URL = appSupportDir.appendingPathComponent("schedules")
    static let legacyClaudeOutputDir: URL = appSupportDir.appendingPathComponent("claude_output")

    static func schedulerDir(for scheduleId: UUID) -> URL {
        let url = schedulersDir.appendingPathComponent(scheduleId.uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func scheduleFile(for scheduleId: UUID) -> URL {
        schedulerDir(for: scheduleId).appendingPathComponent("schedule.json")
    }

    static func claudeOutputDir(for scheduleId: UUID) -> URL {
        let url = schedulerDir(for: scheduleId).appendingPathComponent("claude_output")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func memoryFile(for scheduleId: UUID) -> URL {
        schedulerDir(for: scheduleId).appendingPathComponent("memory.md")
    }

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

    static let userColorsFile: URL = appSupportDir.appendingPathComponent("user_colors.json")
    static let promptsFile: URL = appSupportDir.appendingPathComponent("prompts.json")
    static let promptSettingsFile: URL = appSupportDir.appendingPathComponent("prompt_settings.json")
}
