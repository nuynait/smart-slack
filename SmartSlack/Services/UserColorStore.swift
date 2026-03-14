import SwiftUI

@MainActor
final class UserColorStore: ObservableObject {
    @Published private var colorMap: [String: Int] = [:]

    static let presetColors: [Color] = [
        Color(red: 0.90, green: 0.30, blue: 0.30), // red
        Color(red: 0.85, green: 0.45, blue: 0.25), // orange
        Color(red: 0.80, green: 0.65, blue: 0.20), // amber
        Color(red: 0.55, green: 0.75, blue: 0.25), // lime
        Color(red: 0.30, green: 0.70, blue: 0.40), // green
        Color(red: 0.20, green: 0.70, blue: 0.60), // teal
        Color(red: 0.20, green: 0.65, blue: 0.80), // cyan
        Color(red: 0.30, green: 0.50, blue: 0.85), // blue
        Color(red: 0.45, green: 0.40, blue: 0.85), // indigo
        Color(red: 0.60, green: 0.35, blue: 0.80), // purple
        Color(red: 0.75, green: 0.35, blue: 0.65), // magenta
        Color(red: 0.85, green: 0.35, blue: 0.50), // pink
        Color(red: 0.65, green: 0.50, blue: 0.35), // brown
        Color(red: 0.50, green: 0.55, blue: 0.60), // slate
        Color(red: 0.40, green: 0.60, blue: 0.55), // sage
        Color(red: 0.70, green: 0.55, blue: 0.45), // tan
        Color(red: 0.55, green: 0.40, blue: 0.55), // plum
        Color(red: 0.40, green: 0.55, blue: 0.45), // forest
        Color(red: 0.65, green: 0.40, blue: 0.40), // clay
        Color(red: 0.45, green: 0.50, blue: 0.70), // steel
    ]

    init() {
        load()
    }

    func color(for userId: String) -> Color {
        let index = colorIndex(for: userId)
        return Self.presetColors[index]
    }

    func colorIndex(for userId: String) -> Int {
        if let index = colorMap[userId] {
            return index
        }
        let index = Int.random(in: 0..<Self.presetColors.count)
        colorMap[userId] = index
        save()
        return index
    }

    func setColor(for userId: String, index: Int) {
        colorMap[userId] = index
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Constants.userColorsFile),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        colorMap = map
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(colorMap) else { return }
        try? data.write(to: Constants.userColorsFile)
    }
}
