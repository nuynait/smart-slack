import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var slackTeam: String?
    @Published var slackUser: String?
    @Published var slackUserId: String?
    @Published var slackUserDisplayName: String?
    @Published var userNameCache: [String: String] = [:]

    let scheduleStore = ScheduleStore()
    let logService = LogService()
    let userColorStore = UserColorStore()
    let notificationService = NotificationService()
    let promptStore = PromptStore()
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
