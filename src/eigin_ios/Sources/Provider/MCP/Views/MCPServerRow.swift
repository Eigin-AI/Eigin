import SwiftUI

/// A row in the MCP Servers settings list showing name and tool count.
struct MCPServerRow: View {
    let server: MCPServer
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(server.name)
                .typography(Typography.body)

            if !server.cachedToolNames.isEmpty {
                Text(verbatim: "\(server.cachedToolNames.count) \(Localized.Mcp.tools)")
                    .typography(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
            } else {
                Text(server.url)
                    .typography(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
