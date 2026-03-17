import Foundation
import AppKit

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case htmlUrl = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

@MainActor
final class UpdateService: ObservableObject {
    @Published var latestRelease: GitHubRelease?
    @Published var updateAvailable = false
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    static let repo = "nuynait/smart-slack"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkForUpdates() async {
        isChecking = true
        error = nil

        do {
            let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                error = "Failed to check for updates"
                isChecking = false
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            latestRelease = release

            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            updateAvailable = isNewer(latestVersion, than: currentVersion)
        } catch {
            self.error = error.localizedDescription
        }

        isChecking = false
    }

    func downloadAndInstall() async {
        guard let release = latestRelease,
              let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            error = "No .zip asset found in release. Please download manually."
            if let release = latestRelease, let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        isDownloading = true
        downloadProgress = 0
        error = nil

        do {
            // Download the zip
            let url = URL(string: asset.browserDownloadUrl)!
            let (tempURL, _) = try await URLSession.shared.download(from: url)

            downloadProgress = 0.5

            // Create temp directory for extraction
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SmartSlack-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            // Unzip
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", tempURL.path, "-d", extractDir.path]
            unzipProcess.standardOutput = FileHandle.nullDevice
            unzipProcess.standardError = FileHandle.nullDevice
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                error = "Failed to extract update"
                isDownloading = false
                return
            }

            downloadProgress = 0.75

            // Find the .app in the extracted directory
            let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                error = "No .app found in update archive"
                isDownloading = false
                return
            }

            // Get current app path
            let currentAppPath = Bundle.main.bundlePath
            let currentAppURL = URL(fileURLWithPath: currentAppPath)
            let backupURL = currentAppURL.deletingLastPathComponent()
                .appendingPathComponent("SmartSlack-backup.app")

            // Remove old backup if exists
            try? FileManager.default.removeItem(at: backupURL)

            // Move current app to backup
            try FileManager.default.moveItem(at: currentAppURL, to: backupURL)

            // Move new app to current location
            try FileManager.default.moveItem(at: newApp, to: currentAppURL)

            // Remove quarantine attribute so macOS doesn't re-prompt
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-dr", "com.apple.quarantine", currentAppPath]
            xattrProcess.standardOutput = FileHandle.nullDevice
            xattrProcess.standardError = FileHandle.nullDevice
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            downloadProgress = 1.0

            // Clean up
            try? FileManager.default.removeItem(at: extractDir)
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: backupURL)

            // Relaunch
            relaunch()
        } catch {
            self.error = "Update failed: \(error.localizedDescription)"
            isDownloading = false
        }
    }

    private func relaunch() {
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    private func isNewer(_ version: String, than current: String) -> Bool {
        let v1 = version.split(separator: ".").compactMap { Int($0) }
        let v2 = current.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(v1.count, v2.count)
        for i in 0..<maxLen {
            let a = i < v1.count ? v1[i] : 0
            let b = i < v2.count ? v2[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }
}
