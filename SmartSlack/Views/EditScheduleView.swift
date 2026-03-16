import SwiftUI

struct EditScheduleView: View {
    let schedule: Schedule
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @EnvironmentObject var logService: LogService
    @EnvironmentObject var promptStore: PromptStore
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var intervalSeconds: Double
    @State private var prompt: String
    @State private var notificationMode: NotificationMode
    @State private var skipNotificationMode: NotificationMode

    init(schedule: Schedule) {
        self.schedule = schedule
        _name = State(initialValue: schedule.name)
        _intervalSeconds = State(initialValue: Double(schedule.intervalSeconds))
        _prompt = State(initialValue: schedule.prompt)
        _notificationMode = State(initialValue: schedule.notificationMode)
        _skipNotificationMode = State(initialValue: schedule.skipNotificationMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Schedule")
                .font(.title2.bold())
                .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.headline)
                        TextField("Schedule name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .formCard()

                    HStack {
                        Text("Type")
                            .font(.headline)
                        Spacer()
                        Text(schedule.type.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    .formCard()

                    HStack {
                        Text("Channel")
                            .font(.headline)
                        Spacer()
                        Text(schedule.channelName)
                            .foregroundStyle(.secondary)
                    }
                    .formCard()

                    IntervalPickerView(intervalSeconds: $intervalSeconds)
                        .formCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification Mode")
                            .font(.headline)
                        Picker("", selection: $notificationMode) {
                            Text("Notification").tag(NotificationMode.macosNotification)
                            Text("Force Popup").tag(NotificationMode.forcePopup)
                            Text("Quiet").tag(NotificationMode.quiet)
                        }
                        .pickerStyle(.segmented)
                        Text(notificationModeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .formCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("When Skipped")
                            .font(.headline)
                        Text("Notification when Claude skips based on your filter criteria")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $skipNotificationMode) {
                            Text("Notification").tag(NotificationMode.macosNotification)
                            Text("Force Popup").tag(NotificationMode.forcePopup)
                            Text("Quiet").tag(NotificationMode.quiet)
                        }
                        .pickerStyle(.segmented)
                    }
                    .formCard()

                    PromptInputView(prompt: $prompt)
                }
                .padding(16)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Delete") {
                    schedulerEngine.stopSchedule(schedule.id)
                    logService.deleteLogsForSchedule(schedule.id)
                    scheduleStore.deleteSchedule(schedule)
                    dismiss()
                }
                .buttonStyle(.destructive)

                Button("Save") { save() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || prompt.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private var notificationModeDescription: String {
        switch notificationMode {
        case .macosNotification:
            return "Show a macOS notification when Claude responds. Click to jump to the schedule."
        case .forcePopup:
            return "Show an always-on-top popup with summary and draft. Must send or ignore to dismiss."
        case .quiet:
            return "No notification. Check drafts manually from the sidebar."
        }
    }

    private func save() {
        let promptChanged = prompt != schedule.prompt
        var updated = schedule
        updated.name = name
        updated.intervalSeconds = Int(intervalSeconds)
        updated.prompt = prompt
        updated.notificationMode = notificationMode
        updated.skipNotificationMode = skipNotificationMode
        updated.filterSummary = nil
        updated.memorySummary = nil
        scheduleStore.updateSchedule(updated)

        // Save prompt to history if changed
        if promptChanged {
            let savedPrompt = promptStore.addPrompt(text: prompt)
            Task { await promptStore.generateTags(for: savedPrompt.id) }
        }

        // Always re-analyze filter and memory on save
        appVM.analyzePromptFilter(scheduleId: updated.id, prompt: prompt)
        appVM.analyzePromptMemory(scheduleId: updated.id, prompt: prompt)

        // Restart timer with new interval if active
        if updated.status == .active {
            schedulerEngine.stopSchedule(updated.id)
            schedulerEngine.startSchedule(updated)
        }

        dismiss()
    }



}
