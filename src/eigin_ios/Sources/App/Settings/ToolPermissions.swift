import Factory
import SwiftData
import SwiftUI

/// Per-agent built-in permissions and optional overrides for connected tools.
struct ToolPermissions: View {
    let agent: Agent

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.integrationManager) private var integrationManager
    @Query(sort: \MCPServer.createdAt) private var mcpServers: [MCPServer]
    @Query(sort: \Integration.createdAt) private var integrations: [Integration]
    @State private var builtInLevels: [String: ToolPermissionLevel] = [:]
    @State private var discoveredLevels: [String: ToolPermissionLevel] = [:]
    @State private var showSaveError = false

    private var categories: [ToolCapability.Category] {
        let connected = Set(integrationManager.connectedCapabilities(integrations: integrations)
            .compactMap(\.toolCategory))
        return ToolCapability.Category.allCases.filter {
            !ToolRegistry.capabilities(for: $0)
                .isEmpty && (connected.contains($0) || !isIntegrationBacked($0))
        }
    }

    private var enabledServers: [MCPServer] {
        mcpServers.filter(\.isEnabled)
    }

    private var store: ToolGrantStore {
        ToolGrantStore(context: modelContext, agentID: agent.id)
    }

    var body: some View {
        AppSecondaryScreen(title: Localized.Settings.Permissions.title) {
            if !categories.isEmpty {
                AppContentGroup(label: Localized.Settings.Permissions.builtInTools) {
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        if index > 0 { RowHairline() }
                        AppDisclosure(
                            category.displayName,
                            variant: .open,
                            initiallyExpanded: category == .knowledge
                        ) {
                            PermissionRows(items: ToolRegistry
                                .capabilities(for: category))
                            { capability in
                                PermissionControl(
                                    title: capability.displayName,
                                    segments: ToolPermissionLevel.allCases.map { AppSegment(
                                        $0.displayName,
                                        value: $0
                                    ) },
                                    selection: builtInLevels[capability.key] ?? capability
                                        .defaultPermissionLevel
                                ) { level in
                                    do {
                                        try store.set(capability, level: level)
                                        builtInLevels[capability.key] = level
                                    } catch { showSaveError = true }
                                }
                            }
                        }
                    }
                }
            }
            if !enabledServers.isEmpty {
                AppContentGroup(
                    label: Localized.Settings.Permissions.connectedTools,
                    footnote: Localized.Settings.Permissions.defaultHint
                ) {
                    ForEach(Array(enabledServers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 { RowHairline() }
                        AppDisclosure(server.name, variant: .open) {
                            if server.cachedToolNames.isEmpty {
                                Text(Localized.Mcp.noToolsDiscovered)
                                    .typography(Typography.navTab)
                                    .foregroundStyle(colors.text.standard.muted)
                            } else {
                                PermissionRows(items: server.cachedToolNames) { name in
                                    discoveredControl(server: server, toolName: name)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadGrants() }
        .alert(Localized.Settings.Permissions.saveFailed, isPresented: $showSaveError) {
            Button(Localized.Common.Actions.ok, role: .cancel) { loadGrants() }
        }
    }

    private func discoveredControl(server: MCPServer, toolName: String) -> some View {
        let fullName = Self.mcpToolName(server: server.name, tool: toolName)
        let segments: [AppSegment<ToolPermissionLevel?>] = [
            AppSegment(Localized.Settings.Permissions.defaultLabel, value: nil),
        ] + ToolPermissionLevel.allCases.map { AppSegment($0.displayName, value: Optional($0)) }
        return PermissionControl(
            title: toolName.titleCased,
            segments: segments,
            selection: discoveredLevels[fullName]
        ) { level in
            do {
                try store.setDiscovered(toolName: fullName, level: level)
                discoveredLevels[fullName] = level
            } catch { showSaveError = true }
        }
    }

    /// Uses the same namespaced identity as MCP tool execution.
    static func mcpToolName(server: String, tool: String) -> String {
        MCPNaming.toolName(serverName: server, toolName: tool)
    }

    private func isIntegrationBacked(_ category: ToolCapability.Category) -> Bool {
        BundledIntegrationType.all
            .contains { $0.toolCapabilities.contains { $0.category == category } }
    }

    private func loadGrants() {
        let id = agent.id
        do {
            let rows = try modelContext.fetch(FetchDescriptor<AgentToolGrant>(
                predicate: #Predicate { $0.agentID == id }
            ))
            builtInLevels = [:]
            discoveredLevels = [:]
            for row in rows {
                if row.kind == .discovered { discoveredLevels[row.key] = row.level }
                else { builtInLevels[row.key] = row.level }
            }
        } catch { showSaveError = true }
    }
}

/// A tool name above a standard-height segmented permission control.
private struct PermissionControl<Value: Hashable>: View {
    let title: String
    let segments: [AppSegment<Value>]
    let selection: Value
    let onSelect: (Value) -> Void
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n16) {
            Text(title).typography(Typography.navTab).foregroundStyle(colors.text.standard.base)
            AppSegmentedControl(segments: segments, selection: selection, onSelect: onSelect)
                .accessibilityLabel(title)
        }
    }
}

/// Full-width separators inside a disclosure's existing content insets.
private struct PermissionRows<Item, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(colors.input.standard.inactive).frame(height: 1) }
                content(item)
                    .padding(.top, index == 0 ? 0 : Spacing.n16)
                    .padding(.bottom, index == items.count - 1 ? 0 : Spacing.n16)
            }
        }
    }
}
