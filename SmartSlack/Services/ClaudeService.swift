import Foundation

struct AnalysisResult {
    let summary: String
    let draftReply: String
    let promptSent: String
    let rawResponse: String
    let skipped: Bool
    let memoryReport: String?
}

enum ClaudeService {

    static func analyze(messages: [SlackMessage], prompt: String, channelName: String, scheduleId: UUID, hasFilter: Bool = false, ownerUserId: String? = nil, ownerDisplayName: String? = nil, imagePaths: [String] = [], userNames: [String: String] = [:]) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages, userNames: userNames)
        let ownerContext = ownerIdentityContext(userId: ownerUserId, displayName: ownerDisplayName)
        let memoryFilePath = Constants.memoryFile(for: scheduleId).path
        let memoryFileRef = memoryFileReference(memoryFilePath)
        let imageContext = imagePaths.isEmpty ? "" : "\n\nThe following images were attached to the messages. They have been provided as files for you to view:\n" + imagePaths.map { "- \($0)" }.joined(separator: "\n")
        let dir = prepareOutputDir(for: scheduleId)
        let summaryPath = dir.appendingPathComponent("summary.md").path
        let draftPath = dir.appendingPathComponent("draft.txt").path
        let decisionPath = dir.appendingPathComponent("decision.txt").path
        let memoryReportPath = dir.appendingPathComponent("memory.md").path
        let filterInstruction: String
        if hasFilter {
            filterInstruction = """
            IMPORTANT: First, determine whether these messages are relevant based on the user instructions above.
            The user instructions may contain filters (e.g., "only care about messages related to X" or "only if they mention Y").
            If the messages do NOT match the user's filter criteria, you should SKIP this conversation.
            """
        } else {
            filterInstruction = """
            IMPORTANT: The user has NOT set any filter criteria. You MUST always respond — do NOT skip.
            Always write "respond" to the decision file.
            """
        }

        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".
        \(ownerContext)\(memoryFileRef)
        Here are the new messages:

        \(messagesText)\(imageContext)

        User instructions: \(prompt)

        \(filterInstruction)

        You MUST write exactly three files:

        1. Write your decision to: \(decisionPath)
           - Write ONLY the single word "respond" or "skip" (nothing else)
           \(hasFilter ? "- Write \"skip\" if the messages are not relevant based on the user instructions" : "- You MUST write \"respond\" since no filter is configured")
           - Write "respond" if the messages are relevant and warrant a reply

        2. Write a brief summary of what was discussed to: \(summaryPath)
           - Use markdown formatting (headers, bullet points, bold, etc.) for readability
           - Write this even if you decided to skip (so the user can see what was discussed)

        3. Write your suggested reply to: \(draftPath)
           - Write the reply as if you are the owner speaking
           - Plain text only, this will be sent as a Slack message
           \(hasFilter ? "- If you decided to skip, write a brief explanation of why you skipped (e.g., \"Skipped: messages are about X, not related to the filter criteria\")" : "- Always draft a reply")

        \(memoryManagementSection(memoryFilePath: memoryFilePath, memoryReportPath: memoryReportPath))

        Write the required files now. Do not output anything else.
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
        let memoryFilePath = Constants.memoryFile(for: scheduleId).path
        let memoryFileRef = memoryFileReference(memoryFilePath)
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
        let memoryReportPath = dir.appendingPathComponent("memory.md").path

        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".
        \(ownerContext)\(memoryFileRef)
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

        \(memoryManagementSection(memoryFilePath: memoryFilePath, memoryReportPath: memoryReportPath))

        Write the required files now. Do not output anything else.
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
        let memoryFilePath = Constants.memoryFile(for: scheduleId).path
        let memoryFileRef = memoryFileReference(memoryFilePath)
        let imageContext = imagePaths.isEmpty ? "" : "\n\nThe following images were attached to the messages. They have been provided as files for you to view:\n" + imagePaths.map { "- \($0)" }.joined(separator: "\n")
        let summariesText = allSummaries.enumerated().map { "Session \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
        let dir = prepareOutputDir(for: scheduleId)
        let summaryPath = dir.appendingPathComponent("summary.md").path
        let draftPath = dir.appendingPathComponent("draft.txt").path
        let decisionPath = dir.appendingPathComponent("decision.txt").path
        let memoryReportPath = dir.appendingPathComponent("memory.md").path

        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".
        \(ownerContext)\(memoryFileRef)
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

        \(memoryManagementSection(memoryFilePath: memoryFilePath, memoryReportPath: memoryReportPath))

        Write the required files now. Do not output anything else.
        """

        return try await runClaude(prompt: fullPrompt, scheduleId: scheduleId)
    }

    static func analyzePromptFilter(prompt: String) async throws -> String? {
        let claudePrompt = """
        Analyze the following user prompt for a Slack monitoring tool. Determine if it contains any criteria that would cause the tool to SKIP or NOT REPLY in certain situations. This includes:
        - Topic filters: only care about certain topics, keywords, people, or types of messages
        - Conditional skip: skip if a certain condition is not met (e.g., "skip if no new PRs", "only reply when a release is merged")
        - Event-based triggers: only respond when a specific event happens

        If the prompt contains any skip/filter criteria, respond with a SHORT one-line summary of when it will respond. For example:
        - "Native development, Garcon, mentions of Jerry or Tianyun"
        - "Deployment issues and CI/CD failures"
        - "Questions directed at the owner"
        - "New merged release PRs only"
        - "Only when deployment status changes"

        If the prompt does NOT contain any filtering or skip criteria (it's a general instruction to summarize/respond to everything), respond with exactly "NONE".

        Prompt:
        \(prompt)

        Filter summary (one line, or "NONE"):
        """

        let result = try await runClaudeSimple(prompt: claudePrompt)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "NONE" || trimmed.isEmpty {
            return nil
        }
        return trimmed
    }

    static func analyzePromptMemory(prompt: String) async throws -> String? {
        let claudePrompt = """
        Analyze the following user prompt for a Slack monitoring tool. Determine if it contains ANY instructions — explicit or implicit — to remember, memorize, store, track, or retain ANY kind of information across sessions.

        This includes but is not limited to:
        - Tracking things from conversations (decisions, action items, topics, deadlines)
        - Remembering static values (API keys, credentials, names, preferences, configurations)
        - References to a "memory file" or persistent storage
        - Any phrasing that implies information should persist between runs

        Be inclusive — if there is any hint that something should be remembered or stored, treat it as a memory instruction.

        If the prompt contains memory instructions, respond with a SHORT one-line plaintext of what will be memorized.

        If the prompt truly does NOT contain any memory/remember/track/store instructions, respond with exactly "NONE".

        Prompt:
        \(prompt)

        Memory summary (one line, or "NONE"):
        """

        let result = try await runClaudeSimple(prompt: claudePrompt)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "NONE" || trimmed.isEmpty {
            return nil
        }
        return trimmed
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
        let dir = Constants.claudeOutputDir(for: scheduleId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Internal

    private static func prepareOutputDir(for scheduleId: UUID) -> URL {
        let dir = Constants.claudeOutputDir(for: scheduleId)
        // Clear previous output
        for filename in ["summary.md", "draft.txt", "decision.txt", "memory.md"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
        }
        return dir
    }

    private static func memoryManagementSection(memoryFilePath: String, memoryReportPath: String) -> String {
        return """
        MEMORY MANAGEMENT:
        Review the user instructions above. If the user has asked you to memorize, remember, or track specific information across sessions:
        1. Read the memory file at \(memoryFilePath) if it exists (it may not exist yet — that's fine)
        2. Create or update the memory file at \(memoryFilePath) with the information to remember. Preserve existing entries and add/update as needed.
        3. Write a brief report of what you saved or updated to: \(memoryReportPath)
           - Keep it concise: what was added, updated, or remains unchanged
           - Use markdown formatting for readability

        If the user instructions do NOT ask you to memorize or remember anything, do NOT write the memory report file and do NOT modify the memory file.
        """
    }

    private static func memoryFileReference(_ path: String) -> String {
        let exists = FileManager.default.fileExists(atPath: path)
        if exists {
            return """

            PERSISTENT MEMORY: There is a memory file at \(path) containing context from previous sessions. Read this file for reference before proceeding.
            """
        }
        return ""
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

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    process.waitUntilExit()

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
        let dir = Constants.claudeOutputDir(for: scheduleId)

        let result: (status: Int32, stdout: String, stderr: String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdinPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: Constants.claudePath)
                process.arguments = ["--print", "--output-format", "text", "--allowedTools", "Write,Read,Bash"]
                process.currentDirectoryURL = Constants.schedulerDir(for: scheduleId)
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.standardInput = stdinPipe

                do {
                    try process.run()

                    stdinPipe.fileHandleForWriting.write(prompt.data(using: .utf8)!)
                    stdinPipe.fileHandleForWriting.closeFile()

                    // Read pipes before waitUntilExit to avoid deadlock when output fills the pipe buffer
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    process.waitUntilExit()

                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: (process.terminationStatus, stdout, stderr))
                } catch {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                }
            }
        }

        guard result.status == 0 else {
            // Write debug files for inspection
            try? prompt.write(to: dir.appendingPathComponent("debug_prompt.txt"), atomically: true, encoding: .utf8)
            try? result.stdout.write(to: dir.appendingPathComponent("debug_stdout.txt"), atomically: true, encoding: .utf8)
            try? result.stderr.write(to: dir.appendingPathComponent("debug_stderr.txt"), atomically: true, encoding: .utf8)

            let stderrTrimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutTrimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            var detail = "Claude exited with status \(result.status)"
            detail += "\n  Prompt length: \(prompt.count) chars"
            detail += "\n  Command: \(Constants.claudePath) --print --output-format text --allowedTools Write,Read,Bash"
            if !stderrTrimmed.isEmpty { detail += "\n  stderr: \(String(stderrTrimmed.prefix(500)))" }
            if !stdoutTrimmed.isEmpty { detail += "\n  stdout: \(String(stdoutTrimmed.prefix(500)))" }
            detail += "\n  Debug files saved to: \(dir.path)"
            throw ClaudeError.processError(detail)
        }

        // Read the files Claude wrote
        let summaryFile = dir.appendingPathComponent("summary.md")
        let draftFile = dir.appendingPathComponent("draft.txt")
        let decisionFile = dir.appendingPathComponent("decision.txt")
        let memoryReportFile = dir.appendingPathComponent("memory.md")

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

        // Read memory report if Claude wrote one
        var memoryReport: String?
        if FileManager.default.fileExists(atPath: memoryReportFile.path),
           let report = try? String(contentsOf: memoryReportFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !report.isEmpty {
            memoryReport = report
        }

        return AnalysisResult(summary: summary, draftReply: draftReply, promptSent: prompt, rawResponse: result.stdout, skipped: skipped, memoryReport: memoryReport)
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
