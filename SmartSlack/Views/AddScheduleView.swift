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

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.headline)
                        TextField("Schedule name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .formCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Type")
                            .font(.headline)
                        Picker("", selection: $type) {
                            Text("Channel").tag(ScheduleType.channel)
                            Text("Thread").tag(ScheduleType.thread)
                            Text("DM").tag(ScheduleType.dm)
                            Text("Group DM").tag(ScheduleType.dmgroup)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .onChange(of: type) { _, _ in
                            channelId = ""
                            channelName = ""
                            Task { await loadChannels() }
                        }
                    }
                    .formCard()

                    if isLoadingChannels {
                        ProgressView("Loading channels...")
                            .formCard()
                    } else {
                        ChannelPickerView(
                            channels: filteredChannels,
                            selectedId: $channelId,
                            selectedName: $channelName
                        )
                    }

                    if type == .thread {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Thread TS")
                                .font(.headline)
                            TextField("Thread timestamp", text: $threadTs)
                                .textFieldStyle(.roundedBorder)
                                .help("The ts value of the thread parent message")
                        }
                        .formCard()
                    }

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

                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(16)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") { create() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || channelId.isEmpty || prompt.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 650)
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
            var fetched = try await slackService.listConversations()

            // Resolve DM user IDs to profile names
            let dmChannels = fetched.filter { $0.isIm == true && $0.user != nil }
            for dm in dmChannels {
                guard let userId = dm.user else { continue }
                if let userInfo = try? await slackService.usersInfo(userId: userId) {
                    let profileName = userInfo.profile?.displayName.flatMap({ $0.isEmpty ? nil : $0 })
                        ?? userInfo.profile?.realName.flatMap({ $0.isEmpty ? nil : $0 })
                        ?? userInfo.realName
                        ?? userInfo.name
                        ?? userId
                    if let idx = fetched.firstIndex(where: { $0.id == dm.id }) {
                        fetched[idx].resolvedName = profileName
                    }
                }
            }

            channels = fetched
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

}
