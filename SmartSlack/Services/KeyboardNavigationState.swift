import Foundation

@MainActor
final class KeyboardNavigationState: ObservableObject {
    @Published var showCheatsheet = false
    @Published var showPromptPicker = false   // p key — pick prompt for selected schedule
    @Published var showPromptManager = false  // Cmd+Shift+P — manage prompts standalone

    var isInPromptView: Bool { showPromptPicker || showPromptManager }

    // Sidebar navigation signals
    @Published var sidebarMoveDirection: VerticalDirection?
    @Published var tabCycleDirection: HorizontalDirection?

    // Prompt view navigation signals (shared by picker and manager)
    @Published var promptMoveDirection: VerticalDirection?
    @Published var promptTabCycleDirection: HorizontalDirection?
    @Published var promptAction: PromptAction?
    @Published var focusPromptSearch = false
    @Published var editSelectedSchedule = false
    @Published var deleteSelectedSchedule = false
    @Published var activeReply = false
    @Published var createSchedule = false
    @Published var editAndSend = false
    @Published var rewriteDraft = false
    @Published var ignoreDraft = false
    @Published var toggleSidebar = false

    // Image preview
    @Published var isInImagePreview = false
    @Published var imagePreviewAction: ImagePreviewAction?
    enum ImagePreviewAction { case next, previous, dismiss }
    @Published var confirmingDelete = false
    @Published var confirmDeleteAnswer: Bool?  // true = yes, false = no

    enum VerticalDirection {
        case up, down
    }

    enum HorizontalDirection {
        case left, right
    }

    enum PromptAction {
        case select, edit, dismiss
    }
}
