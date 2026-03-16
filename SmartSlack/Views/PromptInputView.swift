import SwiftUI

struct PromptInputView: View {
    @Binding var prompt: String
    @EnvironmentObject var promptStore: PromptStore
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Prompt")
                    .font(.headline)
                Spacer()
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Label("Use Saved", systemImage: "bookmark")
                        KeyboardHintView(key: "p")
                    }
                }
                .buttonStyle(.smallSecondary)
            }
            TextEditor(text: $prompt)
                .frame(minHeight: 80)
                .font(.body)
        }
        .formCard()
        .sheet(isPresented: $showPicker) {
            PromptPickerView { selectedText in
                prompt = selectedText
            }
            .environmentObject(promptStore)
        }
    }
}
