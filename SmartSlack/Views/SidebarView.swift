import SwiftUI

enum SidebarTab: String, CaseIterable {
    case active = "Active"
    case manual = "Manual"
    case completed = "Completed"
    case failed = "Failed"
}

struct SidebarView: View {
    @EnvironmentObject var scheduleStore: ScheduleStore
    @EnvironmentObject var keyboardNav: KeyboardNavigationState
    @Binding var selectedScheduleId: UUID?
    @State private var selectedTab: SidebarTab = .active

    private var filteredSchedules: [Schedule] {
        scheduleStore.schedules.filter { schedule in
            switch selectedTab {
            case .active: return schedule.status == .active && schedule.intervalSeconds > 0
            case .manual: return schedule.status == .active && schedule.intervalSeconds == 0
            case .completed: return schedule.status == .completed
            case .failed: return schedule.status == .failed
            }
        }
    }

    private var activeCount: Int { scheduleStore.schedules.filter { $0.status == .active && $0.intervalSeconds > 0 }.count }
    private var manualCount: Int { scheduleStore.schedules.filter { $0.status == .active && $0.intervalSeconds == 0 }.count }
    private var completedCount: Int { scheduleStore.schedules.filter { $0.status == .completed }.count }
    private var failedCount: Int { scheduleStore.schedules.filter { $0.status == .failed }.count }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text(activeCount > 0 ? "Active (\(activeCount))" : "Active")
                    .tag(SidebarTab.active)
                Text(manualCount > 0 ? "Manual (\(manualCount))" : "Manual")
                    .tag(SidebarTab.manual)
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
        .onChange(of: keyboardNav.tabCycleDirection) { _, direction in
            guard let direction else { return }
            let tabs = SidebarTab.allCases
            guard let idx = tabs.firstIndex(of: selectedTab) else {
                keyboardNav.tabCycleDirection = nil
                return
            }
            switch direction {
            case .left:
                selectedTab = tabs[(idx - 1 + tabs.count) % tabs.count]
            case .right:
                selectedTab = tabs[(idx + 1) % tabs.count]
            }
            // Select first schedule in new tab if current selection isn't in it
            let schedules = filteredSchedules
            if let id = selectedScheduleId, !schedules.contains(where: { $0.id == id }) {
                selectedScheduleId = schedules.first?.id
            }
            keyboardNav.tabCycleDirection = nil
        }
        .onChange(of: keyboardNav.sidebarMoveDirection) { _, direction in
            guard let direction else { return }
            let schedules = filteredSchedules
            guard !schedules.isEmpty else {
                keyboardNav.sidebarMoveDirection = nil
                return
            }
            let currentIndex = selectedScheduleId.flatMap { id in
                schedules.firstIndex(where: { $0.id == id })
            }
            switch direction {
            case .down:
                if let idx = currentIndex {
                    if idx + 1 < schedules.count {
                        selectedScheduleId = schedules[idx + 1].id
                    }
                } else {
                    selectedScheduleId = schedules.first?.id
                }
            case .up:
                if let idx = currentIndex {
                    if idx > 0 {
                        selectedScheduleId = schedules[idx - 1].id
                    }
                } else {
                    selectedScheduleId = schedules.last?.id
                }
            }
            keyboardNav.sidebarMoveDirection = nil
        }
    }
}
