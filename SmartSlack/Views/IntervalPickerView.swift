import SwiftUI

struct IntervalPickerView: View {
    @Binding var intervalSeconds: Double

    @State private var selectedPresetValue: Double = 300
    @State private var showSlider = false

    private static let presets: [(String, Double)] = [
        ("5s", 5),
        ("30s", 30),
        ("1m", 60),
        ("5m", 300),
        ("10m", 600),
        ("30m", 1800),
        ("1h", 3600),
        ("5h", 18000),
    ]

    private var sliderStep: Double {
        selectedPresetValue >= 3600 ? 60 : 1
    }

    private var sliderRange: ClosedRange<Double> {
        let values = Self.presets.map(\.1)
        guard let idx = values.firstIndex(of: selectedPresetValue) else {
            return 1...299
        }

        let step = sliderStep

        let start: Double
        if idx == 0 {
            start = step
        } else {
            start = values[idx - 1] + step
        }

        let end: Double
        if idx == values.count - 1 {
            end = 86400 // 24h
        } else {
            end = values[idx + 1] - step
        }

        return start...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Check every \(formatInterval(Int(intervalSeconds)))")
                Spacer()
            }

            HStack(spacing: 2) {
                ForEach(Self.presets, id: \.1) { label, value in
                    let isSelected = selectedPresetValue == value
                    Text(label)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showSlider = false
                            selectedPresetValue = value
                            intervalSeconds = value
                            Task {
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                showSlider = true
                            }
                        }
                }
                Spacer()
            }

            if showSlider {
                Slider(value: $intervalSeconds, in: sliderRange, step: sliderStep)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 20)
            }
        }
        .onAppear {
            selectedPresetValue = closestPreset(to: intervalSeconds)
        }
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            showSlider = true
        }
    }

    private func closestPreset(to value: Double) -> Double {
        Self.presets.min(by: { abs($0.1 - value) < abs($1.1 - value) })?.1 ?? 300
    }

    private func formatInterval(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            let minutes = seconds / 60
            let remaining = seconds % 60
            if remaining == 0 { return "\(minutes)m" }
            return "\(minutes)m \(remaining)s"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }
}
