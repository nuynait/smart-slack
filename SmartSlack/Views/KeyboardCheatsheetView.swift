import SwiftUI

struct KeyboardCheatsheetView: View {
    @EnvironmentObject var keyboardNav: KeyboardNavigationState

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    keyboardNav.showCheatsheet = false
                }

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Keyboard shortcuts")
                        .font(.title2.bold())
                    Spacer()
                }

                twoColumnSection("Navigation") {
                    [
                        ("Move down", ["j"]),
                        ("Move up", ["k"]),
                        ("Tab left", ["h"]),
                        ("Tab right", ["l"]),
                    ]
                }

                twoColumnSection("Actions") {
                    [
                        ("New schedule", ["c"]),
                        ("Edit schedule", ["⌘", "E"]),
                        ("Delete schedule", ["d"]),
                        ("Change prompt", ["p"]),
                        ("Manage prompts", ["⌘", "⇧", "P"]),
                        ("Show shortcuts", ["?"]),
                    ]
                }

                twoColumnSection("Draft") {
                    [
                        ("Send / Send to", ["↩"]),
                        ("Edit & Send", ["e"]),
                        ("Rewrite", ["r"]),
                        ("Active reply", ["a"]),
                        ("Ignore", ["i"]),
                    ]
                }

                twoColumnSection("Rewrite / Edit / Active Reply") {
                    [
                        ("Submit", ["⌘", "↩"]),
                        ("Background", ["b"]),
                        ("Cancel", ["Esc"]),
                    ]
                }

                twoColumnSection("Prompt Picker") {
                    [
                        ("Navigate list", ["j", "k"]),
                        ("Switch tabs", ["h", "l"]),
                        ("Search", ["s"]),
                        ("Use prompt", ["Enter"]),
                        ("Edit prompt", ["e"]),
                        ("Close", ["Esc"]),
                    ]
                }
            }
            .padding(24)
            .frame(width: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
        }
    }

    private func twoColumnSection(_ title: String, items: () -> [(String, [String])]) -> some View {
        let list = items()
        let mid = (list.count + 1) / 2
        let left = Array(list.prefix(mid))
        let right = Array(list.suffix(from: mid))

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 6) {
                    ForEach(Array(left.enumerated()), id: \.offset) { _, item in
                        shortcutRow(label: item.0, keys: item.1)
                    }
                }
                .frame(maxWidth: .infinity)

                if !right.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(right.enumerated()), id: \.offset) { _, item in
                            shortcutRow(label: item.0, keys: item.1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func shortcutRow(label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 2) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    keycap(key)
                }
            }
        }
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
    }
}
