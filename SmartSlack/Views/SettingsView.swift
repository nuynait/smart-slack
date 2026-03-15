import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var promptStore: PromptStore
    @State private var showPromptManager = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Text("Notifications")
                        .font(.headline)

                    HStack {
                        Text("System Permission")
                        Spacer()
                        if notificationService.permissionGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.statusActive)
                                .font(.subheadline)
                        } else {
                            Label("Not Granted", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                    }

                    if !notificationService.permissionGranted {
                        HStack(spacing: 12) {
                            Button("Request Permission") {
                                Task { await notificationService.requestPermission() }
                            }
                            .buttonStyle(.primary)

                            Button("Open System Settings") {
                                notificationService.openSystemPreferences()
                            }
                            .buttonStyle(.secondary)
                        }
                    }

                    Text("Notification permission is required for the macOS Notification mode. Force Popup and Quiet modes work without it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .formCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Prompts")
                        .font(.headline)

                    HStack {
                        Text("History Limit")
                        Spacer()
                        Picker("", selection: $promptStore.maxHistoryCount) {
                            ForEach([5, 10, 15, 20, 30, 50], id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        .frame(width: 100)
                    }

                    Text("Maximum number of unsaved prompts to keep in history. Starred prompts are not counted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Manage Prompts") {
                        showPromptManager = true
                    }
                    .buttonStyle(.secondary)
                }
                .formCard()

                if let team = appVM.slackTeam, let user = appVM.slackUser {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account")
                            .font(.headline)
                        Label("Signed in as \(user) (\(team))", systemImage: "person.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .formCard()
                }
            }
            .padding(16)
        }
        .frame(minWidth: 450, minHeight: 350)
        .onAppear {
            Task { await notificationService.checkPermission() }
        }
        .sheet(isPresented: $showPromptManager) {
            PromptManagerView()
                .environmentObject(promptStore)
        }
    }
}
