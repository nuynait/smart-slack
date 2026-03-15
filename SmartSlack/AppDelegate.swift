import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    let appVM = AppViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var window: NSWindow?
    private var forcePopupPanel: NSPanel?

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

        // Watch for force popup requests
        appVM.notificationService.$forcePopupScheduleId
            .receive(on: RunLoop.main)
            .sink { [weak self] scheduleId in
                if let scheduleId {
                    self?.showForcePopup(scheduleId: scheduleId)
                } else {
                    self?.dismissForcePopup()
                }
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

    // MARK: - Force Popup

    private func showForcePopup(scheduleId: UUID) {
        // Dismiss any existing popup
        dismissForcePopup()

        guard let schedule = appVM.scheduleStore.schedule(byId: scheduleId),
              let session = schedule.latestSession else { return }

        let popupView = ForcePopupView(schedule: schedule, session: session)
            .environmentObject(appVM)
            .environmentObject(appVM.scheduleStore)
            .environmentObject(appVM.notificationService)

        let controller = NSHostingController(rootView: popupView)
        let panel = NSPanel(contentViewController: controller)
        panel.title = "SmartSlack — \(schedule.name)"
        panel.setContentSize(NSSize(width: 600, height: 650))
        panel.level = .floating
        panel.styleMask = [.titled, .nonactivatingPanel, .utilityWindow]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        forcePopupPanel = panel
    }

    private func dismissForcePopup() {
        forcePopupPanel?.close()
        forcePopupPanel = nil
    }

    // MARK: - Menu Bar

    private func updateButton() {
        guard let button = statusItem?.button else { return }

        let schedules = appVM.scheduleStore.schedules
        let activeCount = schedules.filter { $0.status == .active }.count
        let failedCount = schedules.filter { $0.status == .failed }.count
        let pendingCount = schedules.filter(\.hasUnresolvedDraft).count

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

        if pendingCount > 0 {
            let pending = NSAttributedString(
                string: " \(pendingCount)",
                attributes: [.foregroundColor: NSColor.systemOrange, .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)]
            )
            attributed.append(pending)
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

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Prevent closing the force popup via the close button
        if sender == forcePopupPanel {
            return false
        }
        return true
    }
}
