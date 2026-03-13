import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var token = ""
    @State private var isConnecting = false
    @State private var showInstructions = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SmartSlack")
                .font(.largeTitle.bold())

            Text("Monitor Slack channels with Claude Code")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Slack User OAuth Token")
                    .font(.headline)

                SecureField("xoxp-...", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)
            }

            if let error = appVM.authError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                isConnecting = true
                Task {
                    await appVM.login(token: token)
                    isConnecting = false
                }
            } label: {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 100)
                } else {
                    Text("Connect")
                        .frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.isEmpty || isConnecting)
            .keyboardShortcut(.defaultAction)

            DisclosureGroup("Setup Instructions", isExpanded: $showInstructions) {
                VStack(alignment: .leading, spacing: 8) {
                    instructionStep(1, "Go to https://api.slack.com/apps → Create New App")
                    instructionStep(2, "Under OAuth & Permissions, add these User Token Scopes:")
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Constants.slackScopes, id: \.self) { scope in
                            Text("  • \(scope)")
                                .font(.caption.monospaced())
                        }
                    }
                    .padding(.leading, 24)
                    instructionStep(3, "Install to Workspace")
                    instructionStep(4, "Copy the User OAuth Token (starts with xoxp-)")
                }
                .padding(.top, 8)
            }
            .frame(width: 400)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption.bold())
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.caption)
        }
    }
}
