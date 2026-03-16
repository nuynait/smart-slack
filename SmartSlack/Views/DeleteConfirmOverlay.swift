import SwiftUI

struct DeleteConfirmOverlay: View {
    let name: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "trash")
                    .font(.title)
                    .foregroundStyle(.red)

                Text("Delete \"\(name)\"?")
                    .font(.headline)

                Text("This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Cancel")
                            KeyboardHintView(key: "n")
                        }
                    }
                    .buttonStyle(.secondary)

                    Button {
                        onConfirm()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Delete")
                            KeyboardHintView(key: "y")
                        }
                    }
                    .buttonStyle(.destructive)
                }
            }
            .padding(24)
            .frame(width: 300)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 5)
        }
    }
}
