import Foundation

struct AnalysisResult {
    let summary: String
    let draftReply: String
    let promptSent: String
    let rawResponse: String
    let skipped: Bool
}

enum ClaudeService {
    private static let outputDir = Constants.claudeOutputDir

    static func analyze(messages: [SlackMessage], prompt: String, channelName: String, scheduleId: UUID, ownerUserId: String? = nil, ownerDisplayName: String? = nil, imagePaths: [String] = [], userNames: [String: String] = [:]) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages, userNames: userNames)
        let ownerContext = ownerIdentityContext(userId: ownerUserId, displayName: ownerDisplayName)
        let imageContext = imagePaths.isEmpty ? "" : "\n\nThe following images were attached to the messages. They have been provided as files for you to view:\n" + imagePaths.map { "- \($0)" }.joined(separator: "\n")
        let dir = prepareOutputDir(for: scheduleId)
        let summaryPath = dir.appendingPathComponent("summary.md").path
        let draftPath = dir.appendingPathComponent("draft.txt").path
        let decisionPath = dir.appendingPathComponent("decision.txt").path
        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".
        \(ownerContext)
        Here are the new messages:

        \(messagesText)\(imageContext)

        User instructions: \(prompt)

        IMPORTANT: First, determine whether these messages are relevant based on the user instructions above.
        The user instructions may contain filters (e.g., "only care about messages related to X" or "only if they mention Y").
        If the messages do NOT match the user's filter criteria, you should SKIP this conversation.

        You MUST write exactly three files:

        1. Write your decision to: \(decisionPath)
           - Write ONLY the single word "respond" or "skip" (nothing else)
           - Write "skip" if the messages are not relevant based on the user instructions
           - Write "respond" if the messages are relevant and warrant a reply

        2. Write a brief summary of what was discussed to: \(summaryPath)
           - Use markdown formatting (headers, bullet points, bold, etc.) for readability
           - Write this even if you decided to skip (so the user can see what was discussed)

        3. Write your suggested reply to: \(draftPath)
           - Write the reply as if you are the owner speaking
           - Plain text only, this will be sent as a Slack message
           - If you decided to skip, write a brief explanation of why you skipped (e.g., "Skipped: messages are about X, not related to the filter criteria")

        Write ALL three files now. Do not output anything else.
        """

        return try await runClaude(prompt: fullPrompt, scheduleId: scheduleId)
    }

    static func rewrite(
        messages: [SlackMessage],
        allSummaries: [String],
        draftHistory: [DraftEntry],
        originalPrompt: String,
        rewritePrompt: String,
        channelName: String,
        scheduleId: UUID,
        ownerUserId: String? = nil,
        ownerDisplayName: String? = nil,
        imagePaths: [String] = [],
        userNames: [String: String] = [:]
    ) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages, userNames: userNames)
        let ownerContext = ownerIdentityContext(userId: ownerUserId, displayName: ownerDisplayName)
        let imageContext = imagePaths.isEmpty ? "" : "\n\nThe following images were attached to the messages. They have been provided as files for you to view:\n" + imagePaths.map { "- \($0)" }.joined(separator: "\n")
        let summariesText = allSummaries.enumerated().map { "Session \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let historyText = draftHistory.map { entry in
            var line = "Draft: \(entry.draft)"
            if let rp = entry.rewritePrompt {
                line += " (rewrite prompt: \(rp))"
            }
            return line
        }.joined(separator: "\n")
        let dir = prepareOutputDir(for: scheduleId)
        let summaryPath = dir.appendingPathComponent("summary.md").path
        let draftPath = dir.appendingPathComponent("draft.txt").path
        let decisionPath = dir.appendingPathComponent("decision.txt").path

        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".
        \(ownerContext)
        Here are the messages:

        \(messagesText)\(imageContext)

        Previous summaries:
        \(summariesText)

        Previous draft attempts (the user was not satisfied with these):
        \(historyText)

        Original instructions: \(originalPrompt)

        The user wants you to rewrite the draft. Their feedback: \(rewritePrompt)

        You MUST write exactly three files:

        1. Write "respond" to: \(decisionPath)

        2. Write an updated summary to: \(summaryPath)
           - Use markdown formatting (headers, bullet points, bold, etc.) for readability

        3. Write a new draft reply incorporating the user's feedback to: \(draftPath)
           - Write the reply as if you are the owner speaking
           - Plain text only, this will be sent as a Slack message

        Write ALL three files now. Do not output anything else.
        """

        return try await runClaude(prompt: fullPrompt, scheduleId: scheduleId)
    }

    static func unskipRewrite(
        messages: [SlackMessage],
        allSummaries: [String],
        originalPrompt: String,
        channelName: String,
        scheduleId: UUID,
        ownerUserId: String? = nil,
        ownerDisplayName: String? = nil,
        imagePaths: [String] = [],
        userNames: [String: String] = [:]
    ) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages, userNames: userNames)
        let ownerContext = ownerIdentityContext(userId: ownerUserId, displayName: ownerDisplayName)
        let imageContext = imagePaths.isEmpty ? "" : "\n\nThe following images were attached to the messages. They have been provided as files for you to view:\n" + imagePaths.map { "- \($0)" }.joined(separator: "\n")
        let summariesText = allSummaries.enumerated().map { "Session \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let dir = prepareOutputDir(for: scheduleId)
        let summaryPath = dir.appendingPathComponent("summary.md").path
        let draftPath = dir.appendingPathComponent("draft.txt").path
        let decisionPath = dir.appendingPathComponent("decision.txt").path

        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".
        \(ownerContext)
        Here are the messages:

        \(messagesText)\(imageContext)

        Previous summaries:
        \(summariesText)

        Original instructions: \(originalPrompt)

        CONTEXT: You previously analyzed these messages and decided to SKIP them because they didn't match the user's filter criteria. However, the user has now explicitly asked you to generate a summary and draft reply anyway. Disregard the filter criteria for this request and provide a helpful response.

        You MUST write exactly three files:

        1. Write "respond" to: \(decisionPath)

        2. Write an updated summary to: \(summaryPath)
           - Use markdown formatting (headers, bullet points, bold, etc.) for readability

        3. Write a draft reply to: \(draftPath)
           - Write the reply as if you are the owner speaking
           - Plain text only, this will be sent as a Slack message

        Write ALL three files now. Do not output anything else.
        """

        return try await runClaude(prompt: fullPrompt, scheduleId: scheduleId)
    }

    static func generateTags(promptText: String, existingTags: [String]) async throws -> [String] {
        let existingList = existingTags.isEmpty
            ? "None yet."
            : existingTags.joined(separator: ", ")

        let prompt = """
        You are a tagging assistant. Given the following prompt text, generate 1-4 short tags that describe its purpose or category.

        IMPORTANT RULES:
        - Reuse existing tags when they fit. Only create new tags if no existing tag applies.
        - Tags should be 1-2 words, lowercase
        - Return ONLY a comma-separated list of tags, nothing else

        Existing tags: \(existingList)

        Prompt text:
        \(promptText)

        Tags:
        """

        let result = try await runClaudeSimple(prompt: prompt)
        let tags = result
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Array(tags.prefix(4))
    }

    static func cleanupOutput(for scheduleId: UUID) {
        let dir = outputDir.appendingPathComponent(scheduleId.uuidString)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Internal

    private static func prepareOutputDir(for scheduleId: UUID) -> URL {
        let dir = outputDir.appendingPathComponent(scheduleId.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Clear previous output
        let summaryFile = dir.appendingPathComponent("summary.md")
        let draftFile = dir.appendingPathComponent("draft.txt")
        try? FileManager.default.removeItem(at: summaryFile)
        try? FileManager.default.removeItem(at: draftFile)
        return dir
    }

    private static func ownerIdentityContext(userId: String?, displayName: String?) -> String {
        guard let userId else { return "" }
        let name = displayName ?? userId
        return """

        IMPORTANT: You are drafting replies on behalf of "\(name)" (Slack user ID: \(userId)).
        Messages from \(name) are from the owner — these may be messages the owner sent manually or replies drafted by a previous session of this tool.
        When writing a draft reply, write in the first person as \(name). Consider what the owner has already said so you don't repeat or contradict their previous messages.
        """
    }

    private static func formatMessages(_ messages: [SlackMessage], userNames: [String: String] = [:]) -> String {
        let mentionPattern = /<@(U[A-Z0-9]+)>/
        return messages.map { msg in
            let userId = msg.user ?? "unknown"
            let displayName = userNames[userId] ?? userId
            var text = msg.text ?? ""
            // Replace <@USERID> mentions with display names
            while let match = text.firstMatch(of: mentionPattern) {
                let mentionedId = String(match.1)
                let mentionedName = userNames[mentionedId] ?? mentionedId
                text.replaceSubrange(match.range, with: "@\(mentionedName)")
            }
            let ts = msg.ts ?? ""
            var line = "[\(ts)] \(displayName): \(text)"
            let images = msg.imageFiles
            if !images.isEmpty {
                let names = images.compactMap(\.name).joined(separator: ", ")
                line += " [attached images: \(names)]"
            }
            return line
        }.joined(separator: "\n")
    }

    private static func runClaudeSimple(prompt: String) async throws -> String {
        let result: (status: Int32, stdout: String, stderr: String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdinPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: Constants.claudePath)
                process.arguments = ["--print", "--output-format", "text"]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.standardInput = stdinPipe

                do {
                    try process.run()
                    stdinPipe.fileHandleForWriting.write(prompt.data(using: .utf8)!)
                    stdinPipe.fileHandleForWriting.closeFile()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: (
                        process.terminationStatus,
                        String(data: stdoutData, encoding: .utf8) ?? "",
                        String(data: stderrData, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                }
            }
        }

        guard result.status == 0 else {
            throw ClaudeError.processError("Claude exited with status \(result.status): \(result.stderr)")
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runClaude(prompt: String, scheduleId: UUID) async throws -> AnalysisResult {
        let dir = outputDir.appendingPathComponent(scheduleId.uuidString)

        let result: (status: Int32, stdout: String, stderr: String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdinPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: Constants.claudePath)
                process.arguments = ["--print", "--output-format", "text", "--allowedTools", "Write"]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.standardInput = stdinPipe

                do {
                    try process.run()

                    stdinPipe.fileHandleForWriting.write(prompt.data(using: .utf8)!)
                    stdinPipe.fileHandleForWriting.closeFile()

                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (process.terminationStatus, stdout, stderr))
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                }
            }
        }

        guard result.status == 0 else {
            throw ClaudeError.processError("Claude exited with status \(result.status): \(result.stderr)")
        }

        // Read the files Claude wrote
        let summaryFile = dir.appendingPathComponent("summary.md")
        let draftFile = dir.appendingPathComponent("draft.txt")
        let decisionFile = dir.appendingPathComponent("decision.txt")

        guard FileManager.default.fileExists(atPath: summaryFile.path) else {
            throw ClaudeError.parseError("Claude did not write summary.md")
        }
        guard FileManager.default.fileExists(atPath: draftFile.path) else {
            throw ClaudeError.parseError("Claude did not write draft.txt")
        }

        let summary = try String(contentsOf: summaryFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let draftReply = try String(contentsOf: draftFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

        // Read decision file — default to "respond" if missing (backward compat)
        var skipped = false
        if FileManager.default.fileExists(atPath: decisionFile.path),
           let decision = try? String(contentsOf: decisionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            skipped = decision == "skip"
        }

        return AnalysisResult(summary: summary, draftReply: draftReply, promptSent: prompt, rawResponse: result.stdout, skipped: skipped)
    }
}

enum ClaudeError: LocalizedError {
    case processError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .processError(let msg): return "Claude process: \(msg)"
        case .parseError(let msg): return "Claude parse: \(msg)"
        }
    }
}
