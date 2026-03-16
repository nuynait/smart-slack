import SwiftUI

struct ImagePreviewOverlay: View {
    let images: [SlackFile]
    let slackService: SlackService?
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool
    @EnvironmentObject var keyboardNav: KeyboardNavigationState

    @State private var loadedImages: [String: NSImage] = [:]

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 12) {
                if selectedIndex < images.count {
                    let file = images[selectedIndex]

                    if let nsImage = loadedImages[file.id] {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 700, maxHeight: 500)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.5), radius: 20)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .frame(width: 200, height: 150)
                    }

                    Text(file.name ?? "Image")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if images.count > 1 {
                    HStack(spacing: 16) {
                        Button {
                            goToPrevious()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                KeyboardHintView(key: "h")
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedIndex == 0)
                        .opacity(selectedIndex == 0 ? 0.3 : 1)

                        Text("\(selectedIndex + 1) / \(images.count)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Button {
                            goToNext()
                        } label: {
                            HStack(spacing: 4) {
                                KeyboardHintView(key: "l")
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedIndex >= images.count - 1)
                        .opacity(selectedIndex >= images.count - 1 ? 0.3 : 1)
                    }
                }
            }
        }
        .onAppear { keyboardNav.isInImagePreview = true }
        .onDisappear { keyboardNav.isInImagePreview = false }
        .onChange(of: keyboardNav.imagePreviewAction) { _, action in
            guard let action else { return }
            switch action {
            case .previous: goToPrevious()
            case .next: goToNext()
            case .dismiss: dismiss()
            }
            keyboardNav.imagePreviewAction = nil
        }
        .task { await loadAllImages() }
    }

    private func dismiss() {
        isPresented = false
        keyboardNav.isInImagePreview = false
    }

    private func goToPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    private func goToNext() {
        if selectedIndex < images.count - 1 {
            selectedIndex += 1
        }
    }

    private func loadAllImages() async {
        for file in images {
            guard loadedImages[file.id] == nil else { continue }
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SmartSlack/thumbs")
            let dest = tempDir.appendingPathComponent("\(file.id).\(file.filetype ?? "png")")

            if FileManager.default.fileExists(atPath: dest.path),
               let img = NSImage(contentsOf: dest) {
                loadedImages[file.id] = img
            } else if let slackService, let url = file.bestThumbUrl {
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try? await slackService.downloadFile(url: url, to: dest)
                if let img = NSImage(contentsOf: dest) {
                    loadedImages[file.id] = img
                }
            }
        }
    }
}
