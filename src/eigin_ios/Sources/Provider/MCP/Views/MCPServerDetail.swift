import Factory
import SwiftData
import SwiftUI

/// Detail view for an MCP server showing connection status and discovered tools.
struct MCPServerDetail: View {
    let server: MCPServer
    @Injected(\.mcpServerManager) private var mcpServerManager
    @Injected(\.mcpOAuthService) private var mcpOAuthService
    @Injected(\.keychainService) private var keychainService
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isReauthorizing = false
    @State private var reauthorizeError: String?
    @State private var showRemoveConfirmation = false

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
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: server.name,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    infoCard
                    statusCard
                    toolsCard
                    removeCard
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(server.name, isPresented: $showRemoveConfirmation) {
            Button(Localized.Ui.remove, role: .destructive) { removeServer() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(Localized.Mcp.removeWarning)
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                infoRow(label: Localized.Mcp.Label.url, value: server.url)
                Divider().padding(.leading, Spacing.n24)
                infoRow(
                    label: Localized.Mcp.authentication,
                    value: server.authType.displayName
                )
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.n16) {
            Text(label)
                .typography(Typography.titleXS)
                .foregroundStyle(colors.text.standard.base)
            Spacer()
            Text(value)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
    }

    // MARK: - Status Card

    private var statusCard: some View {
        AppDisclosure(Localized.Mcp.Section.status, description: status.label) {
            statusDetail
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch status {
        case .idle:
            Text(Localized.Mcp.autoConnectHint)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
        case .connected:
            HStack(spacing: Spacing.n8) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
                Text(Localized.Mcp.Status.connectionActive)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: Spacing.n12) {
                Text(message)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.error)

                if server.authType == .oauth {
                    Button {
                        reauthorize()
                    } label: {
                        if isReauthorizing {
                            ProgressView()
                        } else {
                            Label(Localized.Mcp.reAuthorize, systemImage: "arrow.clockwise")
                                .typography(Typography.tag)
                                .foregroundStyle(colors.accent)
                        }
                    }
                    .disabled(isReauthorizing)

                    if let reauthorizeError {
                        Text(reauthorizeError)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.error)
                    }
                }
            }
        case .disabled:
            Text(Localized.Mcp.Status.disabledHint)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
        }
    }

    // MARK: - Tools Card

    private var toolsCard: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Mcp.tools)

            AppCardSurface(padding: 0) {
                if server.cachedToolNames.isEmpty {
                    HStack {
                        Text(Localized.Mcp.noToolsDiscovered)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.n24)
                    .padding(.vertical, Spacing.n16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(server.cachedToolNames.enumerated()),
                            id: \.element
                        ) { index, toolName in
                            if index > 0 {
                                Divider().padding(.leading, Spacing.n24)
                            }
                            HStack {
                                Text(toolName.titleCased)
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.base)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.n24)
                            .padding(.vertical, Spacing.n16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Remove Card

    private var removeCard: some View {
        AppButton(Localized.Ui.remove, variant: .destructive) {
            showRemoveConfirmation = true
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

    // MARK: - Remove Server

    private func removeServer() {
        for suffix in MCPServer.keychainSuffixes {
            keychainService.delete(key: keychainService.mcpKey(for: server.id, suffix: suffix))
        }
        modelContext.delete(server)
        dismiss()
    }

    // MARK: - Status

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

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}
