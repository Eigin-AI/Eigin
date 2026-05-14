import SwiftUI

/// A row in the MCP Servers settings list showing name and tool count.
struct MCPServerRow: View {
    let server: MCPServer
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n4) {
            Text(server.name)
                .typography(Typography.body)

            if !server.cachedToolNames.isEmpty {
                Text(verbatim: "\(server.cachedToolNames.count) \(Localized.Mcp.tools)")
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
            } else {
                Text(server.url)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
                    .lineLimit(1)
            }
        }
    }
}
