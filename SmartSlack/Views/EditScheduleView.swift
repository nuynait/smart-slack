import SwiftUI

struct EditScheduleView: View {
    let schedule: Schedule
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
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

            Form {
                TextField("Name", text: $name)

                HStack {
                    Text("Type")
                    Spacer()
                    Text(schedule.type.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Channel")
                    Spacer()
                    Text(schedule.channelName)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    Text("Check every \(formatInterval(Int(intervalSeconds)))")
                    Slider(value: $intervalSeconds, in: 5...1800, step: 5)
                }

                VStack(alignment: .leading) {
                    Text("Prompt")
                        .font(.headline)
                    TextEditor(text: $prompt)
                        .frame(minHeight: 80)
                        .font(.body)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Delete", role: .destructive) {
                    schedulerEngine.stopSchedule(schedule.id)
                    scheduleStore.deleteSchedule(schedule)
                    dismiss()
                }

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
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

    private func formatInterval(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        if remaining == 0 { return "\(minutes)m" }
        return "\(minutes)m \(remaining)s"
    }
}
