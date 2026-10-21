import Factory
import SwiftData
import SwiftUI

/// Configuration screen for per-agent tool permission levels.
///
/// Displays all capability categories and MCP servers as ``AppDisclosure``
/// foldouts in a single card. Each capability and MCP tool uses an
/// ``AppOptionPicker`` to select its permission level.
struct ToolPermissions: View {
    let agent: Agent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Query(sort: \MCPServer.createdAt) private var mcpServers: [MCPServer]
    @Query(sort: \Integration.createdAt) private var integrations: [Integration]
    @State private var builtInLevels: [String: ToolPermissionLevel] = [:]
    @State private var discoveredLevels: [String: ToolPermissionLevel] = [:]

    private var permissionOptions: [AppOption<ToolPermissionLevel>] {
        ToolPermissionLevel.allCases.map { AppOption($0.displayName, value: $0) }
    }

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                // All built-in capability categories in one card.
                // Integration-backed categories (email, family & school)
                // only appear once something provides them.
                let integrationCategories = Set(
                    Container.shared.integrationManager()
                        .connectedCapabilities(integrations: integrations)
                        .compactMap(\.toolCategory)
                )
                let categories = ToolCapability.Category.allCases
                    .filter { !ToolRegistry.capabilities(for: $0).isEmpty }
                    .filter { integrationCategories.contains($0) || !isIntegrationBacked($0) }

                if !categories.isEmpty {
                    AppCardSurface(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(categories.enumerated()),
                                id: \.element
                            ) { index, category in
                                let capabilities = ToolRegistry.capabilities(for: category)

                                if index > 0 {
                                    Divider().padding(.horizontal, Spacing.n24)
                                }

                                AppDisclosure(category.displayName, variant: .open) {
                                    VStack(spacing: Spacing.n16) {
                                        ForEach(capabilities, id: \.key) { capability in
                                            AppOptionPicker(
                                                title: capability.displayName,
                                                options: permissionOptions,
                                                selection: builtInLevels[capability.key]
                                                    ?? capability.defaultPermissionLevel
                                            ) { newLevel in
                                                builtInLevels[capability.key] = newLevel
                                                persistGrant(
                                                    capability: capability,
                                                    level: newLevel
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // MCP per-server overrides in one card
                if !enabledServers.isEmpty {
                    AppCardSurface(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(enabledServers.enumerated()),
                                id: \.element.id
                            ) { index, server in
                                if index > 0 {
                                    Divider().padding(.horizontal, Spacing.n24)
                                }

                                AppDisclosure(server.name, variant: .open) {
                                    if server.cachedToolNames.isEmpty {
                                        Text(Localized.Mcp.noToolsDiscovered)
                                            .typography(Typography.tag)
                                            .foregroundStyle(colors.text.standard.muted)
                                    } else {
                                        VStack(spacing: Spacing.n16) {
                                            ForEach(
                                                server.cachedToolNames,
                                                id: \.self
                                            ) { toolName in
                                                mcpToolPicker(
                                                    server: server,
                                                    toolName: toolName
                                                )
                                            }
                                        }
                                    }
                                }
                                .onAppear { loadGrants() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: Localized.Settings.Permissions.title,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { loadGrants() }
    }

    // MARK: - MCP Tool Picker

    private func mcpToolPicker(server: MCPServer, toolName: String) -> some View {
        let fullName = Self.mcpToolName(server: server.name, tool: toolName)
        let currentValue = discoveredLevels[fullName]

        let options: [AppOption<ToolPermissionLevel?>] = [
            AppOption(Localized.Settings.Permissions.defaultLabel, value: nil),
        ] + ToolPermissionLevel.allCases.map {
            AppOption($0.displayName, value: Optional($0))
        }

        return AppOptionPicker(
            title: toolName.titleCased,
            options: options,
            selection: currentValue
        ) { newLevel in
            discoveredLevels[fullName] = newLevel
            persistDiscoveredGrant(toolName: fullName, level: newLevel)
        }
    }

    // MARK: - MCP Tool Name

    /// Builds the full namespaced tool name matching MCPToolProxy's convention.
    static func mcpToolName(server: String, tool: String) -> String {
        let sanitizedServer = server
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return "mcp__\(sanitizedServer)__\(tool)"
    }

    // MARK: - Data

    private var enabledServers: [MCPServer] {
        mcpServers.filter(\.isEnabled)
    }

    /// Whether a category's tools only exist through a connected integration.
    /// Derived from the bundled catalog so it stays in sync as domains grow.
    private func isIntegrationBacked(_ category: ToolCapability.Category) -> Bool {
        BundledIntegrationType.all.contains {
            $0.toolCapabilities.contains { $0.category == category }
        }
    }

    private func loadGrants() {
        let agentID = agent.id
        let descriptor = FetchDescriptor<AgentToolGrant>(
            predicate: #Predicate { $0.agentID == agentID }
        )
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        for row in rows {
            if row.kind == .discovered {
                discoveredLevels[row.key] = row.level
            } else {
                builtInLevels[row.key] = row.level
            }
        }
    }

    private func persistGrant(capability: ToolCapability, level: ToolPermissionLevel) {
        let agentID = agent.id
        let capabilityKey = capability.key
        let descriptor = FetchDescriptor<AgentToolGrant>(
            predicate: #Predicate { $0.agentID == agentID && $0.key == capabilityKey }
        )
        let existing = try? modelContext.fetch(descriptor)
        let existingByKind = existing?.filter { $0.kind == capability.kind }

        if level == capability.defaultPermissionLevel {
            if let row = existingByKind?.first {
                modelContext.delete(row)
            }
        } else if let row = existingByKind?.first {
            row.level = level
        } else {
            let grant = AgentToolGrant(agentID: agentID, capability: capability, level: level)
            modelContext.insert(grant)
        }
    }

    private func persistDiscoveredGrant(toolName: String, level: ToolPermissionLevel?) {
        let agentID = agent.id
        let descriptor = FetchDescriptor<AgentToolGrant>(
            predicate: #Predicate { $0.agentID == agentID && $0.key == toolName }
        )
        let existing = try? modelContext.fetch(descriptor)
        let existingDiscovered = existing?.filter { $0.kind == .discovered }

        if let level {
            if let row = existingDiscovered?.first {
                row.level = level
            } else {
                let cap = ToolCapability(
                    kind: .discovered, key: toolName,
                    displayName: toolName,
                    defaultPermissionLevel: .ask, category: .extensions
                )
                let grant = AgentToolGrant(agentID: agentID, capability: cap, level: level)
                modelContext.insert(grant)
            }
        } else {
            if let row = existingDiscovered?.first {
                modelContext.delete(row)
            }
        }
    }
}
