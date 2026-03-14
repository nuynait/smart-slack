import SwiftUI

enum SidebarTab: String, CaseIterable {
    case active = "Active"
    case completed = "Completed"
    case failed = "Failed"
}

struct SidebarView: View {
    @EnvironmentObject var scheduleStore: ScheduleStore
    @Binding var selectedScheduleId: UUID?
    @State private var selectedTab: SidebarTab = .active

    private var filteredSchedules: [Schedule] {
        scheduleStore.schedules.filter { schedule in
            switch selectedTab {
            case .active: return schedule.status == .active
            case .completed: return schedule.status == .completed
            case .failed: return schedule.status == .failed
            }
        }
    }

    private var activeCount: Int { scheduleStore.schedules.filter { $0.status == .active }.count }
    private var completedCount: Int { scheduleStore.schedules.filter { $0.status == .completed }.count }
    private var failedCount: Int { scheduleStore.schedules.filter { $0.status == .failed }.count }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text(activeCount > 0 ? "Active (\(activeCount))" : "Active")
                    .tag(SidebarTab.active)
                Text(completedCount > 0 ? "Done (\(completedCount))" : "Done")
                    .tag(SidebarTab.completed)
                Text(failedCount > 0 ? "Failed (\(failedCount))" : "Failed")
                    .tag(SidebarTab.failed)
            }
            .pickerStyle(.segmented)
            .padding(8)

            List(filteredSchedules, selection: $selectedScheduleId) { schedule in
                ScheduleRowView(schedule: schedule)
                    .tag(schedule.id)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onChange(of: scheduleStore.schedules) { _, _ in
            syncTabToSelection()
        }
        .onChange(of: selectedScheduleId) { _, _ in
            syncTabToSelection()
        }
    }

    private func syncTabToSelection() {
        guard let id = selectedScheduleId,
              let schedule = scheduleStore.schedule(byId: id) else { return }
        let needed: SidebarTab = switch schedule.status {
        case .active: .active
        case .completed: .completed
        case .failed: .failed
        }
        if selectedTab != needed {
            selectedTab = needed
        }
    }
}
