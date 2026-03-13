import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        Group {
            if appVM.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
    }
}
