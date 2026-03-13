import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    let appVM = AppViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        appVM.scheduleStore.$schedules
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateButton()
            }
            .store(in: &cancellables)

        updateButton()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @objc private func statusItemClicked() {
        if let window = NSApplication.shared.windows.first(where: { $0.title == "SmartSlack" || $0.isKeyWindow }) {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        let schedules = appVM.scheduleStore.schedules
        let activeCount = schedules.filter { $0.status == .active }.count
        let failedCount = schedules.filter { $0.status == .failed }.count

        let attributed = NSMutableAttributedString()

        // SF Symbol
        if let image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right.fill", accessibilityDescription: "SmartSlack") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let configured = image.withSymbolConfiguration(config) ?? image
            let attachment = NSTextAttachment()
            attachment.image = configured
            attributed.append(NSAttributedString(attachment: attachment))
        }

        if activeCount > 0 {
            let active = NSAttributedString(
                string: " \(activeCount)",
                attributes: [.foregroundColor: NSColor.systemGreen, .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)]
            )
            attributed.append(active)
        }

        if failedCount > 0 {
            let failed = NSAttributedString(
                string: " \(failedCount)",
                attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)]
            )
            attributed.append(failed)
        }

        button.attributedTitle = attributed
    }
}
