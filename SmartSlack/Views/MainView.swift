import SwiftUI

struct MainView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var selectedScheduleId: UUID?
    @State private var showAddFromLinkSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedScheduleId: $selectedScheduleId)
        } detail: {
            if let id = selectedScheduleId,
               let schedule = scheduleStore.schedule(byId: id) {
                ScheduleDetailView(schedule: schedule)
            } else {
                ContentUnavailableView(
                    "No Schedule Selected",
                    systemImage: "calendar.badge.clock",
                    description: Text("Select a schedule from the sidebar or create a new one")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddFromLinkSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("History") {
                        openHistory()
                    }
                    .keyboardShortcut("h", modifiers: [.command, .shift])

                    Button("Log Viewer") {
                        if let id = selectedScheduleId,
                           let schedule = scheduleStore.schedule(byId: id) {
                            openLogViewer(scheduleId: id, name: schedule.name)
                        }
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(selectedScheduleId == nil)

                    Divider()

                    if let team = appVM.slackTeam, let user = appVM.slackUser {
                        Text("Signed in as \(user) (\(team))")
                    }

                    Button("Sign Out", role: .destructive) {
                        appVM.logout()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddFromLinkSheet) {
            AddScheduleFromLinkView()
        }
    }

    private func openHistory() {
        let historyView = HistoryView()
            .environmentObject(scheduleStore)
        let controller = NSHostingController(rootView: historyView)
        let window = NSWindow(contentViewController: controller)
        window.title = "SmartSlack History"
        window.setContentSize(NSSize(width: 750, height: 550))
        window.makeKeyAndOrderFront(nil)
    }

    private func openLogViewer(scheduleId: UUID, name: String) {
        let logView = LogViewerView(scheduleId: scheduleId, scheduleName: name)
            .environmentObject(appVM.logService)
        let controller = NSHostingController(rootView: logView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Logs — \(name)"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.makeKeyAndOrderFront(nil)
    }
}
