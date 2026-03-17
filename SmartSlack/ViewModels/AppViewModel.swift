import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var slackTeam: String?
    @Published var slackTeamUrl: String?
    @Published var slackUser: String?
    @Published var slackUserId: String?
    @Published var slackUserDisplayName: String?
    @Published var userNameCache: [String: String] = [:]
    @Published var analyzingFilterScheduleIds: Set<UUID> = []
    @Published var analyzingMemoryScheduleIds: Set<UUID> = []

    let scheduleStore = ScheduleStore()
    let logService = LogService()
    let userColorStore = UserColorStore()
    let notificationService = NotificationService()
    let promptStore = PromptStore()
    let updateService = UpdateService()
    lazy var schedulerEngine = SchedulerEngine(scheduleStore: scheduleStore, logService: logService)

    private(set) var slackService: SlackService?
    private var pendingUserLookups = Set<String>()

    init() {
        schedulerEngine.setUserNameResolver(
            { [weak self] in self?.userNameCache ?? [:] },
            updater: { [weak self] names in
                guard let self else { return }
                self.userNameCache.merge(names) { _, new in new }
            }
        )
        schedulerEngine.setNotificationService(notificationService)
        if let token = KeychainService.loadToken() {
            slackService = SlackService(token: token)
            schedulerEngine.setSlackService(slackService!)
            isAuthenticated = true
            Task { await validateAndStart() }
        }
        Task { await updateService.checkForUpdates() }
    }

    func login(token: String) async {
        authError = nil
        let service = SlackService(token: token)

        do {
            let result = try await service.authTest()
            guard result.ok else {
                authError = result.error ?? "Authentication failed"
                return
            }

            _ = KeychainService.save(token: token)
            slackService = service
            schedulerEngine.setSlackService(service)
            slackTeam = result.team
            slackTeamUrl = result.url
            slackUser = result.user
            slackUserId = result.userId
            isAuthenticated = true

            await resolveOwnerProfile(service: service, userId: result.userId)
            schedulerEngine.setOwner(userId: slackUserId, displayName: slackUserDisplayName)
            schedulerEngine.startAllActive()
        } catch {
            authError = error.localizedDescription
        }
    }

    func logout() {
        schedulerEngine.stopAll()
        KeychainService.deleteToken()
        slackService = nil
        isAuthenticated = false
        slackTeam = nil
        slackTeamUrl = nil
        slackUser = nil
        slackUserId = nil
        slackUserDisplayName = nil
    }

    func resolveUserNames(ids: [String]) {
        guard let slackService else { return }
        let unknown = ids.filter { userNameCache[$0] == nil && !pendingUserLookups.contains($0) }
        guard !unknown.isEmpty else { return }
        for id in unknown { pendingUserLookups.insert(id) }

        Task {
            for userId in unknown {
                if let info = try? await slackService.usersInfo(userId: userId) {
                    let name = info.profile?.displayName.flatMap({ $0.isEmpty ? nil : $0 })
                        ?? info.profile?.realName.flatMap({ $0.isEmpty ? nil : $0 })
                        ?? info.realName
                        ?? info.name
                        ?? userId
                    userNameCache[userId] = name
                }
                pendingUserLookups.remove(userId)
            }
        }
    }

    func displayName(for userId: String) -> String {
        userNameCache[userId] ?? userId
    }

    /// Construct a Slack message link for use with AddScheduleFromLinkView.
    /// Format: https://workspace.slack.com/archives/CHANNEL_ID/pTIMESTAMP
    func slackMessageLink(channelId: String, messageTs: String) -> String? {
        guard let baseUrl = slackTeamUrl?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return nil }
        // Convert ts "1234567890.123456" -> "p1234567890123456"
        let pTs = "p" + messageTs.replacingOccurrences(of: ".", with: "")
        return "\(baseUrl)/archives/\(channelId)/\(pTs)"
    }

    func analyzePromptFilter(scheduleId: UUID, prompt: String) {
        analyzingFilterScheduleIds.insert(scheduleId)
        logService.log(.info, scheduleId: scheduleId, message: "Analyzing prompt for filter criteria")

        Task {
            var filter: String?
            do {
                filter = try await ClaudeService.analyzePromptFilter(prompt: prompt)
            } catch {
                logService.log(.error, scheduleId: scheduleId, message: "Filter analysis failed: \(error.localizedDescription)")
            }

            if let filter {
                logService.log(.info, scheduleId: scheduleId, message: "Filter detected: \(filter)")
            } else {
                logService.log(.info, scheduleId: scheduleId, message: "No filter detected in prompt")
            }

            guard var sched = scheduleStore.schedule(byId: scheduleId) else {
                analyzingFilterScheduleIds.remove(scheduleId)
                return
            }
            sched.filterSummary = filter
            scheduleStore.updateSchedule(sched)
            analyzingFilterScheduleIds.remove(scheduleId)
        }
    }

    func analyzePromptMemory(scheduleId: UUID, prompt: String) {
        analyzingMemoryScheduleIds.insert(scheduleId)
        logService.log(.info, scheduleId: scheduleId, message: "Analyzing prompt for memory instructions")

        Task {
            var memorySummary: String?
            do {
                memorySummary = try await ClaudeService.analyzePromptMemory(prompt: prompt)
            } catch {
                logService.log(.error, scheduleId: scheduleId, message: "Memory analysis failed: \(error.localizedDescription)")
            }

            if let memorySummary {
                logService.log(.info, scheduleId: scheduleId, message: "Memory detected: \(memorySummary)")
            } else {
                logService.log(.info, scheduleId: scheduleId, message: "No memory instructions in prompt")
            }

            guard var sched = scheduleStore.schedule(byId: scheduleId) else {
                analyzingMemoryScheduleIds.remove(scheduleId)
                return
            }
            sched.memorySummary = memorySummary
            scheduleStore.updateSchedule(sched)
            analyzingMemoryScheduleIds.remove(scheduleId)
        }
    }

    private func resolveOwnerProfile(service: SlackService, userId: String?) async {
        guard let userId else { return }
        if let info = try? await service.usersInfo(userId: userId) {
            slackUserDisplayName = info.profile?.displayName.flatMap({ $0.isEmpty ? nil : $0 })
                ?? info.profile?.realName.flatMap({ $0.isEmpty ? nil : $0 })
                ?? info.realName
                ?? info.name
                ?? userId
            userNameCache[userId] = slackUserDisplayName
        }
    }

    private func validateAndStart() async {
        guard let slackService else { return }
        do {
            let result = try await slackService.authTest()
            if result.ok {
                slackTeam = result.team
                slackTeamUrl = result.url
                slackUser = result.user
                slackUserId = result.userId
                await resolveOwnerProfile(service: slackService, userId: result.userId)
                schedulerEngine.setOwner(userId: slackUserId, displayName: slackUserDisplayName)
                schedulerEngine.startAllActive()
            } else {
                logout()
            }
        } catch {
            logout()
        }
    }
}
