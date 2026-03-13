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
                HStack {
                    Text("Active")
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .tag(SidebarTab.active)

                HStack {
                    Text("Done")
                    if completedCount > 0 {
                        Text("\(completedCount)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .tag(SidebarTab.completed)

                HStack {
                    Text("Failed")
                    if failedCount > 0 {
                        Text("\(failedCount)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
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
    }
}
