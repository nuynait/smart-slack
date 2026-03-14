import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Block types

    private enum Block {
        case heading(Int, String)       // level, text
        case bullet(String)             // text (may contain inline markdown)
        case numberedItem(String, String) // number, text
        case paragraph(String)          // text (may contain inline markdown)
    }

    // MARK: - Parsing

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var paragraphBuffer = ""

        func flushParagraph() {
            let trimmed = paragraphBuffer.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                blocks.append(.paragraph(trimmed))
            }
            paragraphBuffer = ""
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Headings: # ## ###
            if let match = trimmed.firstMatch(of: /^(#{1,3})\s+(.+)$/) {
                flushParagraph()
                let level = match.1.count
                blocks.append(.heading(level, String(match.2)))
                continue
            }

            // Bullet: - or *
            if let match = trimmed.firstMatch(of: /^[-*]\s+(.+)$/) {
                flushParagraph()
                blocks.append(.bullet(String(match.1)))
                continue
            }

            // Numbered list: 1. 2. etc.
            if let match = trimmed.firstMatch(of: /^(\d+)\.\s+(.+)$/) {
                flushParagraph()
                blocks.append(.numberedItem(String(match.1), String(match.2)))
                continue
            }

            // Regular text — accumulate into paragraph
            if !paragraphBuffer.isEmpty {
                paragraphBuffer += " "
            }
            paragraphBuffer += trimmed
        }

        flushParagraph()
        return blocks
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(headingFont(level))
                .padding(.top, level == 1 ? 4 : 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(.secondary)
                inlineMarkdown(text)
            }
            .padding(.leading, 8)
        case .numberedItem(let num, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
                inlineMarkdown(text)
            }
            .padding(.leading, 8)
        case .paragraph(let text):
            inlineMarkdown(text)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .headline
        case 2: return .subheadline.bold()
        default: return .subheadline
        }
    }

    // MARK: - Inline markdown (bold, italic, code, links)

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }
}
