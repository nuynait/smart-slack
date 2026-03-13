import SwiftUI

@main
struct SmartSlackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("SmartSlack", id: "main") {
            ContentView()
                .environmentObject(appDelegate.appVM)
                .environmentObject(appDelegate.appVM.scheduleStore)
                .environmentObject(appDelegate.appVM.schedulerEngine)
                .environmentObject(appDelegate.appVM.logService)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
