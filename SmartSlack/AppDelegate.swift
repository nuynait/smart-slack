import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    let appVM = AppViewModel()
    let keyboardNav = KeyboardNavigationState()
    private var cancellables = Set<AnyCancellable>()
    private var window: NSWindow?
    private var forcePopupPanel: NSPanel?
    private var eventMonitor: Any?

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

        appVM.updateService.$updateAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateButton()
            }
            .store(in: &cancellables)

        // Watch for force popup requests (react when the front of the queue changes)
        appVM.notificationService.$popupQueue
            .receive(on: RunLoop.main)
            .map { $0.first }
            .removeDuplicates()
            .sink { [weak self] scheduleId in
                if let scheduleId {
                    self?.showForcePopup(scheduleId: scheduleId)
                } else {
                    self?.dismissForcePopup()
                }
            }
            .store(in: &cancellables)

        updateButton()
        installKeyboardMonitor()

        // Ensure the main window is visible on launch (SwiftUI may delay creation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.findMainWindow()?.isVisible != true {
                NSApplication.shared.activate(ignoringOtherApps: true)
                self?.findMainWindow()?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @objc private func statusItemClicked() {
        // Find the main app window (exclude panels, popups, and other utility windows)
        if let window = findMainWindow() {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } else {
            // Window not yet created by SwiftUI — activate app to trigger window creation
            NSApplication.shared.activate(ignoringOtherApps: true)
            // SwiftUI may create the window asynchronously; try again after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if let window = self?.findMainWindow() {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    private func findMainWindow() -> NSWindow? {
        NSApplication.shared.windows.first(where: {
            $0.title == "SmartSlack" && !($0 is NSPanel)
        })
    }

    // MARK: - Keyboard Navigation

    private func installKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func isTextFieldActive() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Let text fields handle their own input
        if isTextFieldActive() { return event }

        // Don't handle keys when force popup is active
        if forcePopupPanel?.isKeyWindow == true { return event }

        guard let chars = event.charactersIgnoringModifiers else { return event }

        // Image preview mode — h/l/Esc/arrows
        if keyboardNav.isInImagePreview {
            if chars == "h" || event.keyCode == 123 { // h or left arrow
                keyboardNav.imagePreviewAction = .previous
                return nil
            }
            if chars == "l" || event.keyCode == 124 { // l or right arrow
                keyboardNav.imagePreviewAction = .next
                return nil
            }
            if event.keyCode == 53 { // Esc
                keyboardNav.imagePreviewAction = .dismiss
                return nil
            }
            return event
        }

        // Delete confirmation mode — y/n/Esc
        if keyboardNav.confirmingDelete {
            if chars == "y" {
                keyboardNav.confirmDeleteAnswer = true
                return nil
            }
            if chars == "n" || event.keyCode == 53 {
                keyboardNav.confirmDeleteAnswer = false
                return nil
            }
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Shift+P — open prompt manager (standalone, no schedule context)
        if chars == "p" && flags.contains(.command) && flags.contains(.shift) {
            keyboardNav.showPromptManager = true
            return nil
        }

        // Cmd+E — edit schedule
        if chars == "e" && flags.contains(.command) {
            keyboardNav.editSelectedSchedule = true
            return nil
        }

        // Only handle bare keys from here (allow Shift for ?)
        guard flags.subtracting(.shift).isEmpty else { return event }

        // Prompt view mode (picker or manager)
        if keyboardNav.isInPromptView {
            switch chars {
            case "j":
                keyboardNav.promptMoveDirection = .down
                return nil
            case "k":
                keyboardNav.promptMoveDirection = .up
                return nil
            case "h":
                keyboardNav.promptTabCycleDirection = .left
                return nil
            case "l":
                keyboardNav.promptTabCycleDirection = .right
                return nil
            case "e":
                keyboardNav.promptAction = .edit
                return nil
            case "s":
                keyboardNav.focusPromptSearch = true
                return nil
            case "?":
                keyboardNav.showCheatsheet.toggle()
                return nil
            default:
                // Enter key — only selects in picker mode
                if event.keyCode == 36 && keyboardNav.showPromptPicker {
                    keyboardNav.promptAction = .select
                    return nil
                }
                // Escape key
                if event.keyCode == 53 {
                    if keyboardNav.showCheatsheet {
                        keyboardNav.showCheatsheet = false
                    } else {
                        keyboardNav.promptAction = .dismiss
                    }
                    return nil
                }
                return event
            }
        }

        // Global mode
        switch chars {
        case "?":
            keyboardNav.showCheatsheet.toggle()
            return nil
        case "j":
            keyboardNav.sidebarMoveDirection = .down
            return nil
        case "k":
            keyboardNav.sidebarMoveDirection = .up
            return nil
        case "h":
            keyboardNav.tabCycleDirection = .left
            return nil
        case "l":
            keyboardNav.tabCycleDirection = .right
            return nil
        case "p":
            keyboardNav.showPromptPicker = true
            return nil
        case "e":
            keyboardNav.editAndSend = true
            return nil
        case "r":
            keyboardNav.rewriteDraft = true
            return nil
        case "a":
            keyboardNav.activeReply = true
            return nil
        case "i":
            keyboardNav.ignoreDraft = true
            return nil
        case "d":
            keyboardNav.deleteSelectedSchedule = true
            return nil
        case "c":
            keyboardNav.createSchedule = true
            return nil
        default:
            // Escape closes cheatsheet
            if event.keyCode == 53 && keyboardNav.showCheatsheet {
                keyboardNav.showCheatsheet = false
                return nil
            }
            return event
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
            .environmentObject(appVM.schedulerEngine)
            .environmentObject(appVM.notificationService)
            .environmentObject(appVM.userColorStore)

        let controller = NSHostingController(rootView: popupView)
        let panel = NSPanel(contentViewController: controller)
        panel.title = "SmartSlack — \(schedule.name)"
        panel.setContentSize(NSSize(width: 650, height: 700))
        panel.level = .screenSaver
        panel.styleMask = [.titled, .utilityWindow]
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
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
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            let configured = image.withSymbolConfiguration(config) ?? image
            let attachment = NSTextAttachment()
            attachment.image = configured
            attributed.append(NSAttributedString(attachment: attachment))
        }

        let countFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)

        if activeCount > 0 {
            attributed.append(NSAttributedString(
                string: "\(activeCount)",
                attributes: [.foregroundColor: NSColor.systemGreen, .font: countFont]
            ))
        }

        if pendingCount > 0 {
            attributed.append(NSAttributedString(
                string: "\(pendingCount)",
                attributes: [.foregroundColor: NSColor.systemOrange, .font: countFont]
            ))
        }

        if failedCount > 0 {
            attributed.append(NSAttributedString(
                string: "\(failedCount)",
                attributes: [.foregroundColor: NSColor.systemRed, .font: countFont]
            ))
        }

        if appVM.updateService.updateAvailable {
            attributed.append(NSAttributedString(
                string: "\u{2191}",
                attributes: [.foregroundColor: NSColor.systemBlue, .font: countFont]
            ))
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
