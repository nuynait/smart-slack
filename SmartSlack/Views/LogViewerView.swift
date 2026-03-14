import SwiftUI

struct LogViewerView: View {
    let scheduleId: UUID
    let scheduleName: String
    @EnvironmentObject var logService: LogService
    @State private var filterLevel: LogLevel = .info
    @State private var autoScroll = true
    @State private var isAutoScrolling = false

    private var filteredLogs: [LogEntry] {
        logService.logs.filter { entry in
            entry.scheduleId == scheduleId && entry.level >= filterLevel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Level", selection: $filterLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .frame(width: 150)

                Spacer()

                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .help(autoScroll ? "Auto-scroll enabled" : "Auto-scroll disabled")

                Button {
                    logService.loadLogs(scheduleId: scheduleId)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload logs")

                Button {
                    logService.clearLogs(for: scheduleId)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear logs")
            }
            .padding(8)

            Divider()

            if filteredLogs.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text",
                    description: Text("No log entries match the current filter")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredLogs) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(entry.timestamp.shortFormatted)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 140, alignment: .leading)

                                    Text(entry.level.rawValue.uppercased())
                                        .font(.caption.monospaced().bold())
                                        .foregroundStyle(levelColor(entry.level))
                                        .frame(width: 60)

                                    Text(entry.message)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .id(entry.id)
                            }
                            // Invisible anchor at the very bottom — track visibility
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .named("logScroll")).maxY) { _, maxY in
                                        // If not currently doing a programmatic scroll,
                                        // user scrolled away from bottom → disable auto-scroll
                                        if !isAutoScrolling && autoScroll {
                                            // Bottom anchor is off-screen if maxY > container height + threshold
                                            // We just check if it moved significantly
                                            autoScroll = false
                                        }
                                    }
                            }
                            .frame(height: 1)
                            .id("bottom")
                        }
                    }
                    .coordinateSpace(name: "logScroll")
                    .onChange(of: filteredLogs.count) { _, _ in
                        if autoScroll {
                            scrollToBottom(proxy)
                        }
                    }
                    .onChange(of: autoScroll) { _, isOn in
                        if isOn {
                            scrollToBottom(proxy)
                        }
                    }
                    .onAppear {
                        if autoScroll {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToBottom(proxy)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: 700, minHeight: 400)
        .onAppear {
            logService.loadLogs(scheduleId: scheduleId)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        isAutoScrolling = true
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        // Reset flag well after scroll animation settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isAutoScrolling = false
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .verbose: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
