import Foundation

struct AnalysisResult {
    let summary: String
    let draftReply: String
}

enum ClaudeService {
    static func analyze(messages: [SlackMessage], prompt: String, channelName: String) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages)
        let fullPrompt = """
        You are monitoring a Slack channel/conversation called "\(channelName)".

        Here are the new messages:

        \(messagesText)

        User instructions: \(prompt)

        Based on the messages and instructions above, provide your response as a JSON object with exactly two fields:
        - "summary": a brief summary of what was discussed in the new messages
        - "draft_reply": your suggested reply based on the user's instructions

        Respond ONLY with valid JSON, no markdown fences or extra text:
        {"summary": "...", "draft_reply": "..."}
        """

        return try await runClaude(prompt: fullPrompt)
    }

    static func rewrite(
        messages: [SlackMessage],
        allSummaries: [String],
        draftHistory: [DraftEntry],
        originalPrompt: String,
        rewritePrompt: String,
        channelName: String
    ) async throws -> AnalysisResult {
        let messagesText = formatMessages(messages)
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

        Here are the messages:

        \(messagesText)

        Previous summaries:
        \(summariesText)

        Previous draft attempts (the user was not satisfied with these):
        \(historyText)

        Original instructions: \(originalPrompt)

        The user wants you to rewrite the draft. Their feedback: \(rewritePrompt)

        Provide your response as a JSON object with exactly two fields:
        - "summary": an updated summary
        - "draft_reply": a new draft reply incorporating the user's feedback

        Respond ONLY with valid JSON, no markdown fences or extra text:
        {"summary": "...", "draft_reply": "..."}
        """

        return try await runClaude(prompt: fullPrompt)
    }

    // MARK: - Internal

    private static func formatMessages(_ messages: [SlackMessage]) -> String {
        messages.map { msg in
            let user = msg.user ?? "unknown"
            let text = msg.text ?? ""
            let ts = msg.ts ?? ""
            return "[\(ts)] <\(user)>: \(text)"
        }.joined(separator: "\n")
    }

    private static func runClaude(prompt: String) async throws -> AnalysisResult {
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
        return try parseResult(output)
    }

    private static func parseResult(_ output: String) throws -> AnalysisResult {
        // Try to extract JSON from the output, handling potential markdown fences
        var jsonString = output
        if let startRange = output.range(of: "{"),
           let endRange = output.range(of: "}", options: .backwards) {
            jsonString = String(output[startRange.lowerBound...endRange.upperBound])
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

        return AnalysisResult(summary: summary, draftReply: draftReply)
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
