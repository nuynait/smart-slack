import SwiftUI

struct SlackImageView: View {
    let file: SlackFile
    let slackService: SlackService?

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 180)
                    .cornerRadius(6)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 80, height: 60)
                    .background(.quaternary)
                    .cornerRadius(6)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                    Text(file.name ?? "image")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.quaternary)
                .cornerRadius(6)
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let slackService, let url = file.bestThumbUrl else { return }
        isLoading = true
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SmartSlack/thumbs")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let dest = tempDir.appendingPathComponent("\(file.id).\(file.filetype ?? "png")")

            if FileManager.default.fileExists(atPath: dest.path) {
                image = NSImage(contentsOf: dest)
            } else {
                try await slackService.downloadFile(url: url, to: dest)
                image = NSImage(contentsOf: dest)
            }
        } catch {
            // Silently fail - show placeholder
        }
        isLoading = false
    }
}
