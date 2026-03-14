import Foundation

struct AnalysisResult {
    let summary: String
    let draftReply: String
    let promptSent: String
    let rawResponse: String
}

enum ClaudeService {
    static func analyze(messages: [SlackMessage], prompt: String, channelName: String, ownerUserId: String? = nil, ownerDisplayName: String? = nil, imagePaths: [String] = []) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages)
        let ownerContext = ownerIdentityContext(userId: ownerUserId, displayName: ownerDisplayName)
        let imageContext = imagePaths.isEmpty ? "" : "\n\nThe following images were attached to the messages. They have been provided as files for you to view:\n" + imagePaths.map { "- \($0)" }.joined(separator: "\n")
        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".
        \(ownerContext)
        Here are the new messages:

        \(messagesText)\(imageContext)

        User instructions: \(prompt)

        Based on the messages and instructions above, provide your response as a JSON object with exactly two fields:
        - "summary": a brief summary of what was discussed in the new messages
        - "draft_reply": your suggested reply based on the user's instructions. Write the reply as if you are the owner speaking.

        Respond ONLY with valid JSON, no markdown fences or extra text:
        {"summary": "...", "draft_reply": "..."}
        """

        return try await runClaude(prompt: fullPrompt, rawPrompt: fullPrompt, imagePaths: imagePaths)
    }

    static func rewrite(
        messages: [SlackMessage],
        allSummaries: [String],
        draftHistory: [DraftEntry],
        originalPrompt: String,
        rewritePrompt: String,
        channelName: String,
        ownerUserId: String? = nil,
        ownerDisplayName: String? = nil,
        imagePaths: [String] = []
    ) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages)
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

        Provide your response as a JSON object with exactly two fields:
        - "summary": an updated summary
        - "draft_reply": a new draft reply incorporating the user's feedback. Write the reply as if you are the owner speaking.

        Respond ONLY with valid JSON, no markdown fences or extra text:
        {"summary": "...", "draft_reply": "..."}
        """

        return try await runClaude(prompt: fullPrompt, rawPrompt: fullPrompt, imagePaths: imagePaths)
    }

    // MARK: - Internal

    private static func ownerIdentityContext(userId: String?, displayName: String?) -> String {
        guard let userId else { return "" }
        let name = displayName ?? userId
        return """

        IMPORTANT: You are drafting replies on behalf of "\(name)" (Slack user ID: \(userId)).
        Messages from <\(userId)> are from the owner — these may be messages the owner sent manually or replies drafted by a previous session of this tool.
        When writing a draft reply, write in the first person as \(name). Consider what the owner has already said so you don't repeat or contradict their previous messages.
        """
    }

    private static func formatMessages(_ messages: [SlackMessage]) -> String {
        messages.map { msg in
            let user = msg.user ?? "unknown"
            let text = msg.text ?? ""
            let ts = msg.ts ?? ""
            var line = "[\(ts)] <\(user)>: \(text)"
            let images = msg.imageFiles
            if !images.isEmpty {
                let names = images.compactMap(\.name).joined(separator: ", ")
                line += " [attached images: \(names)]"
            }
            return line
        }.joined(separator: "\n")
    }

    private static func runClaude(prompt: String, rawPrompt: String, imagePaths: [String] = []) async throws -> AnalysisResult {
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

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return try parseResult(output, promptSent: rawPrompt)
    }

    private static func parseResult(_ output: String, promptSent: String) throws -> AnalysisResult {
        // Try to extract JSON from the output, handling potential markdown fences
        var jsonString = output
        if let startRange = output.range(of: "{"),
           let endRange = output.range(of: "}", options: .backwards),
           startRange.lowerBound < endRange.upperBound {
            jsonString = String(output[startRange.lowerBound..<endRange.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeError.parseError("Could not convert output to data")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.parseError("Output is not a JSON object")
        }

        guard let summary = json["summary"] as? String,
              let draftReply = json["draft_reply"] as? String else {
            throw ClaudeError.parseError("Missing 'summary' or 'draft_reply' fields")
        }

        return AnalysisResult(summary: summary, draftReply: draftReply, promptSent: promptSent, rawResponse: output)
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
