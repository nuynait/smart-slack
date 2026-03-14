import SwiftUI

struct MainView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var selectedScheduleId: UUID?
    @State private var showAddSheet = false
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
                Menu {
                    Button("Browse Channels") {
                        showAddSheet = true
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button("From Message Link") {
                        showAddFromLinkSheet = true
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("History") {
                        openHistory()
                    }
                    .keyboardShortcut("h", modifiers: [.command, .shift])

                    Button("Log Viewer") {
                        openLogViewer()
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])

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
        .sheet(isPresented: $showAddSheet) {
            AddScheduleView()
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

    private func openLogViewer() {
        let logView = LogViewerView()
            .environmentObject(appVM.logService)
            .environmentObject(appVM.scheduleStore)
        let controller = NSHostingController(rootView: logView)
        let window = NSWindow(contentViewController: controller)
        window.title = "SmartSlack Logs"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.makeKeyAndOrderFront(nil)
    }
}
