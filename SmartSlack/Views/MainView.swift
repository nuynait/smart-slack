import SwiftUI

struct MainView: View {
    @EnvironmentObject var appVM: AppViewModel
    @EnvironmentObject var scheduleStore: ScheduleStore
    @State private var selectedScheduleId: UUID?
    @State private var showAddSheet = false

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
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
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
    }

    private func openLogViewer() {
        let logView = LogViewerView()
            .environmentObject(appVM.logService)
        let controller = NSHostingController(rootView: logView)
        let window = NSWindow(contentViewController: controller)
        window.title = "SmartSlack Logs"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.makeKeyAndOrderFront(nil)
    }
}
