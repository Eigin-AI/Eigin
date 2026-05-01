#if DEBUG
import SwiftUI

struct LogViewer: View {
    @Environment(\.colors) private var colors
    @AppStorage(StorageKey.logDebugMode) private var debugMode = false
    @State private var logText = ""
    @State private var searchText = ""

    private var filteredLines: [String] {
        let lines = logText.components(separatedBy: "\n")
        guard !searchText.isEmpty else { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if logText.isEmpty {
                    Text(Localized.Settings.Log.empty)
                        .font(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                        .padding()
                } else {
                    ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 1)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Filter log")
        .navigationTitle("App Log")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    logText = AppLogger.readLog()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                if let url = AppLogger.exportLog() {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Button(role: .destructive) {
                    AppLogger.clearLog()
                    logText = ""
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            logText = AppLogger.readLog()
        }
    }
}

#Preview {
    NavigationStack {
        LogViewer()
    }
    .previewEnvironment()
}
#endif
