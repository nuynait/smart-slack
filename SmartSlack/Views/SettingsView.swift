import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var promptStore: PromptStore
    @EnvironmentObject var keyboardNav: KeyboardNavigationState
    @State private var showPromptManager = false
    @AppStorage("showNotificationModeInSidebar") private var showNotificationMode = false

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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Display")
                        .font(.headline)

                    Toggle("Show notification mode in sidebar", isOn: $showNotificationMode)

                    Text("Show an icon next to each schedule indicating its notification mode (Notification, Force Popup, or Quiet).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .formCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Updates")
                        .font(.headline)

                    HStack {
                        Text("Current Version")
                        Spacer()
                        Text("v\(appVM.updateService.currentVersion)")
                            .foregroundStyle(.secondary)
                    }

                    if appVM.updateService.updateAvailable, let release = appVM.updateService.latestRelease {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                            Text("Update available: \(release.tagName)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        }

                        if let body = release.body, !body.isEmpty {
                            Text(body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }

                        if appVM.updateService.isDownloading {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: appVM.updateService.downloadProgress)
                                    .tint(.blue)
                                Text("Downloading and installing...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Download & Install") {
                                Task { await appVM.updateService.downloadAndInstall() }
                            }
                            .buttonStyle(.primary)
                        }
                    } else {
                        Button {
                            Task { await appVM.updateService.checkForUpdates() }
                        } label: {
                            if appVM.updateService.isChecking {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking...")
                                }
                            } else {
                                Text("Check for Updates")
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(appVM.updateService.isChecking)
                    }

                    if let error = appVM.updateService.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
                .environmentObject(keyboardNav)
        }
    }
}
