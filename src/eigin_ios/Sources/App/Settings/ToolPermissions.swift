import SwiftData
import SwiftUI

/// Configuration screen for per-agent tool permission levels.
///
/// Displays each ``ToolCapability`` grouped by category with a picker
/// to set the permission level (Always / Ask / Never).
/// MCP servers get their own sections with per-tool overrides.
struct ToolPermissions: View {
    let agent: Agent

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Query(sort: \MCPServer.createdAt) private var mcpServers: [MCPServer]
    @State private var builtInLevels: [String: ToolPermissionLevel] = [:]
    @State private var discoveredLevels: [String: ToolPermissionLevel] = [:]

    var body: some View {
        Form {
            // Built-in capabilities grouped by category
            ForEach(ToolCapability.Category.allCases, id: \.self) { category in
                Section {
                    ForEach(ToolRegistry.capabilities(for: category), id: \.key) { capability in
                        Picker(capability.displayName, selection: binding(for: capability)) {
                            ForEach(ToolPermissionLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                    }
                    .listRowBackground(colors.surface)
                } header: {
                    Label(category.displayName, systemImage: category.systemImage)
                        .typography(Typography.label)
                }
            }

            // MCP per-tool overrides
            if !enabledServers.isEmpty {
                Section {
                    ForEach(enabledServers) { server in
                        DisclosureGroup {
                            ForEach(server.cachedToolNames, id: \.self) { toolName in
                                let fullName = Self.mcpToolName(server: server.name, tool: toolName)
                                Picker(
                                    toolName.titleCased,
                                    selection: mcpToolBinding(fullName: fullName)
                                ) {
                                    Text(Localized.Settings.Permissions.defaultLabel)
                                        .tag(ToolPermissionLevel?.none)
                                    ForEach(ToolPermissionLevel.allCases, id: \.self) { level in
                                        Text(level.displayName)
                                            .tag(ToolPermissionLevel?.some(level))
                                    }
                                }
                            }
                            .onAppear { loadGrants() }
                        } label: {
                            Label(server.name, systemImage: "server.rack")
                                .typography(Typography.subheadline)
                        }
                    }
                    .listRowBackground(colors.surface)
                } header: {
                    Label(Localized.Settings.Permissions.mcpServers, systemImage: "server.rack")
                        .typography(Typography.label)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(Localized.Settings.Permissions.title, style: Typography.largeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadGrants() }
    }

    private var enabledServers: [MCPServer] {
        mcpServers.filter(\.isEnabled)
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

    private func binding(for capability: ToolCapability) -> Binding<ToolPermissionLevel> {
        Binding(
            get: { builtInLevels[capability.key] ?? capability.defaultPermissionLevel },
            set: { newLevel in
                builtInLevels[capability.key] = newLevel
                persistGrant(capability: capability, level: newLevel)
            }
        )
    }

    private func mcpToolBinding(fullName: String) -> Binding<ToolPermissionLevel?> {
        Binding(
            get: { discoveredLevels[fullName] },
            set: { newLevel in
                discoveredLevels[fullName] = newLevel
                persistDiscoveredGrant(toolName: fullName, level: newLevel)
            }
        )
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
            // Remove override — default applies
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
                    defaultPermissionLevel: .ask, category: .external
                )
                let grant = AgentToolGrant(agentID: agentID, capability: cap, level: level)
                modelContext.insert(grant)
            }
        } else {
            // nil = "Default" — remove the override
            if let row = existingDiscovered?.first {
                modelContext.delete(row)
            }
        }
    }
}
