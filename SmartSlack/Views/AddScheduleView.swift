import SwiftUI

struct AddScheduleView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var schedulerEngine: SchedulerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: ScheduleType = .channel
    @State private var channelId = ""
    @State private var channelName = ""
    @State private var threadTs = ""
    @State private var intervalSeconds: Double = 300
    @State private var prompt = ""
    @State private var channels: [SlackChannel] = []
    @State private var isLoadingChannels = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("New Schedule")
                .font(.title2.bold())
                .padding()

            Form {
                TextField("Name", text: $name)

                Picker("Type", selection: $type) {
                    Text("Channel").tag(ScheduleType.channel)
                    Text("Thread").tag(ScheduleType.thread)
                    Text("DM").tag(ScheduleType.dm)
                    Text("Group DM").tag(ScheduleType.dmgroup)
                }
                .onChange(of: type) { _, _ in
                    channelId = ""
                    channelName = ""
                    Task { await loadChannels() }
                }

                if isLoadingChannels {
                    ProgressView("Loading channels...")
                } else {
                    Picker("Channel", selection: $channelId) {
                        Text("Select...").tag("")
                        ForEach(filteredChannels) { ch in
                            Text(ch.displayName).tag(ch.id)
                        }
                    }
                    .onChange(of: channelId) { _, newValue in
                        channelName = filteredChannels.first { $0.id == newValue }?.displayName ?? ""
                    }
                }

                if type == .thread {
                    TextField("Thread TS", text: $threadTs)
                        .help("The ts value of the thread parent message")
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

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || channelId.isEmpty || prompt.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .task { await loadChannels() }
    }

    private var filteredChannels: [SlackChannel] {
        channels.filter { ch in
            switch type {
            case .channel: return ch.isChannel == true || ch.isGroup == true
            case .thread: return ch.isChannel == true || ch.isGroup == true
            case .dm: return ch.isIm == true
            case .dmgroup: return ch.isMpim == true
            }
        }
    }

    private func loadChannels() async {
        guard let slackService = appVM.slackService else { return }
        isLoadingChannels = true
        do {
            channels = try await slackService.listConversations()
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingChannels = false
    }

    private func create() {
        let schedule = Schedule(
            id: UUID(),
            name: name,
            type: type,
            channelId: channelId,
            threadTs: type == .thread ? threadTs : nil,
            channelName: channelName,
            prompt: prompt,
            intervalSeconds: Int(intervalSeconds),
            status: .active,
            createdAt: Date(),
            lastRun: nil,
            lastMessageTs: nil,
            sessions: []
        )

        scheduleStore.saveSchedule(schedule)
        schedulerEngine.startSchedule(schedule)
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
