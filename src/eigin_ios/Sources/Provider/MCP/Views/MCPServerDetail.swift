import Factory
import SwiftUI

/// Detail view for an MCP server showing connection status and discovered tools.
struct MCPServerDetail: View {
    let server: MCPServer
    @Injected(\.mcpServerManager) private var mcpServerManager
    @Injected(\.mcpOAuthService) private var mcpOAuthService
    @Environment(\.colors) private var colors
    @State private var statusExpanded = false
    @State private var isReauthorizing = false
    @State private var reauthorizeError: String?

    private var status: ConnectionStatus {
        if !server.isEnabled {
            .disabled
        } else if let error = mcpServerManager.connectionErrors[server.id] {
            .error(error)
        } else if mcpServerManager.isConnected(serverID: server.id) {
            .connected
        } else {
            .idle
        }
    }

    var body: some View {
        List {
            Section {
                Group {
                    LabeledContent(Localized.Mcp.Label.url, value: server.url)
                    LabeledContent(
                        Localized.Mcp.authentication,
                        value: server.authType.displayName
                    )
                }
                .listRowBackground(colors.surface.standard.alternative)
            }

            Section {
                DisclosureGroup(isExpanded: $statusExpanded) {
                    statusDetail
                } label: {
                    HStack(spacing: Spacing.n8) {
                        statusIndicator
                        Text(status.label)
                            .typography(Typography.navTab)
                            .foregroundStyle(colors.text.standard.base)
                    }
                }
                .listRowBackground(colors.surface.standard.alternative)
            } header: {
                Text(Localized.Mcp.Section.status)
                    .typography(Typography.miniLabel)
            }

            Section {
                Group {
                    if server.cachedToolNames.isEmpty {
                        Text(Localized.Mcp.noToolsDiscovered)
                            .foregroundStyle(colors.text.standard.muted)
                    } else {
                        ForEach(server.cachedToolNames, id: \.self) { toolName in
                            Label(toolName.titleCased, systemImage: "wrench")
                                .typography(Typography.navTab)
                                .foregroundStyle(colors.text.standard.base)
                        }
                    }
                }
                .listRowBackground(colors.surface.standard.alternative)
            } header: {
                Text(Localized.Mcp.tools)
                    .typography(Typography.miniLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(server.name, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle, .disabled:
            Image(systemName: "circle")
                .foregroundStyle(colors.text.standard.muted)
                .font(.caption2)
        case .connected:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(colors.text.standard.error)
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch status {
        case .idle:
            Text(Localized.Mcp.autoConnectHint)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        case .connected:
            Text(Localized.Mcp.Status.connectionActive)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        case .error(let message):
            VStack(alignment: .leading, spacing: Spacing.n8) {
                Text(message)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.error)

                if server.authType == .oauth {
                    Button {
                        reauthorize()
                    } label: {
                        if isReauthorizing {
                            ProgressView()
                        } else {
                            Label(Localized.Mcp.reAuthorize, systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isReauthorizing)

                    if let reauthorizeError {
                        Text(reauthorizeError)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.error)
                    }
                }
            }
        case .disabled:
            Text(Localized.Mcp.Status.disabledHint)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
    }

    // MARK: - Re-authorize

    private func reauthorize() {
        guard let serverURL = URL(string: server.url) else { return }
        isReauthorizing = true
        reauthorizeError = nil

        Task {
            do {
                let config = try await mcpOAuthService.discoverOAuth(for: serverURL)
                guard let config else {
                    // Server is now open — clear tokens and reconnect
                    mcpOAuthService.clearTokens(for: server.id)
                    await mcpServerManager.disconnect(serverID: server.id)
                    isReauthorizing = false
                    return
                }

                _ = try await mcpOAuthService.authorize(config: config, serverID: server.id)

                // Force reconnect with new tokens
                await mcpServerManager.disconnect(serverID: server.id)
                isReauthorizing = false
            } catch MCPOAuthError.userCancelled {
                isReauthorizing = false
            } catch {
                reauthorizeError = error.localizedDescription
                isReauthorizing = false
            }
        }
    }

    private enum ConnectionStatus {
        case idle
        case connected
        case error(String)
        case disabled

        var label: String {
            switch self {
            case .idle: Localized.Mcp.Status.notConnected
            case .connected: Localized.Mcp.Status.connected
            case .error: Localized.Status.error
            case .disabled: Localized.Mcp.Status.disabled
            }
        }
    }
}
