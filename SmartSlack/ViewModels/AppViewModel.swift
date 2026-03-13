import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authError: String?
    @Published var slackTeam: String?
    @Published var slackUser: String?

    let scheduleStore = ScheduleStore()
    let logService = LogService()
    lazy var schedulerEngine = SchedulerEngine(scheduleStore: scheduleStore, logService: logService)

    private(set) var slackService: SlackService?

    init() {
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
            isAuthenticated = true

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
    }

    private func validateAndStart() async {
        guard let slackService else { return }
        do {
            let result = try await slackService.authTest()
            if result.ok {
                slackTeam = result.team
                slackUser = result.user
                schedulerEngine.startAllActive()
            } else {
                logout()
            }
        } catch {
            logout()
        }
    }
}
