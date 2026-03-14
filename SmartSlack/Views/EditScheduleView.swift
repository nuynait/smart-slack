import SwiftUI

struct EditScheduleView: View {
    let schedule: Schedule
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @EnvironmentObject var logService: LogService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var intervalSeconds: Double
    @State private var prompt: String

    init(schedule: Schedule) {
        self.schedule = schedule
        _name = State(initialValue: schedule.name)
        _intervalSeconds = State(initialValue: Double(schedule.intervalSeconds))
        _prompt = State(initialValue: schedule.prompt)
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
                        Text("Prompt")
                            .font(.headline)
                        TextEditor(text: $prompt)
                            .frame(minHeight: 80)
                            .font(.body)
                    }
                    .formCard()
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
                    ClaudeService.cleanupOutput(for: schedule.id)
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
        .frame(width: 500, height: 450)
    }

    private func save() {
        var updated = schedule
        updated.name = name
        updated.intervalSeconds = Int(intervalSeconds)
        updated.prompt = prompt
        scheduleStore.updateSchedule(updated)

        // Restart timer with new interval if active
        if updated.status == .active {
            schedulerEngine.stopSchedule(updated.id)
            schedulerEngine.startSchedule(updated)
        }

        dismiss()
    }

}
