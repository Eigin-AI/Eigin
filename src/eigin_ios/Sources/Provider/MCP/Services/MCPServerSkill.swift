import Foundation

/// Projects saved MCP connections and bundled presets into skills without connecting.
enum MCPServerSkill {
    /// Includes unconnected presets and enabled custom servers, with distinct skill IDs.
    static func project(servers: [MCPServer]) -> [Skill] {
        var seenIDs: Set<String> = []
        return servers.filter { $0.isEnabled && !isPresetServer($0) }.map { server in
            let id = assignID(to: server, disambiguating: &seenIDs)
            return skill(id: id, server: server)
        } + MCPPreset.all.map { presetSkill($0, servers: servers) }
    }

    /// Resolves a preset or enabled custom server skill by ID.
    static func skill(forID id: String, servers: [MCPServer]) -> Skill? {
        project(servers: servers).first { $0.id == id }
    }

    /// Resolves the underlying server backing a projected skill ID, if any —
    /// used to connect the right server on activation.
    static func server(forSkillID id: String, servers: [MCPServer]) -> MCPServer? {
        if let preset = MCPPreset.forSkillID(id) {
            return preset.server(in: servers).flatMap { $0.isEnabled ? $0 : nil }
        }
        var seenIDs: Set<String> = []
        return servers.filter { $0.isEnabled && !isPresetServer($0) }.first { server in
            assignID(to: server, disambiguating: &seenIDs) == id
        }
    }

    private static func isPresetServer(_ server: MCPServer) -> Bool {
        MCPPreset.all.contains { $0.id == server.presetID }
    }

    private static func presetSkill(_ preset: MCPPreset, servers: [MCPServer]) -> Skill {
        let server = preset.server(in: servers).flatMap { $0.isEnabled ? $0 : nil }
        let connected = server.map { skill(id: preset.skillID, server: $0) }
        let instructions = [preset.instructions, connected?.instruction].compactMap { $0 }
            .joined(separator: "\n\n")
        return Skill(
            id: preset.skillID, displayName: preset.displayName,
            description: preset.description, instruction: instructions,
            smallInstruction: preset.instructions,
            requiredTools: connected?.requiredTools ?? [], alwaysActive: false,
            customDescriptor: "Dinero Danish accounting: invoices, bookkeeping, purchases, payments, financial reports and account setup.",
            connectionPresetID: server == nil ? preset.id : nil
        )
    }

    // MARK: - ID assignment

    /// Two servers can sanitize to the same skill ID (e.g. both named
    /// "Notes"). `seenIDs` tracks IDs already handed out in this projection
    /// pass; on a collision, a short suffix from the server's UUID is
    /// appended so every server still gets a stable, unique ID.
    private static func assignID(
        to server: MCPServer,
        disambiguating seenIDs: inout Set<String>
    ) -> String {
        var id = MCPNaming.skillID(serverName: server.name)
        if seenIDs.contains(id) {
            id += "_\(server.id.uuidString.prefix(4).lowercased())"
        }
        seenIDs.insert(id)
        return id
    }

    // MARK: - Projection

    private static func skill(id: String, server: MCPServer) -> Skill {
        let toolNames = server.cachedToolNames.sorted()
        let requiredTools: Set<ToolCapability> = Set(toolNames.map { toolName in
            ToolCapability(
                kind: .discovered,
                key: MCPNaming.toolName(serverName: server.toolNamespace, toolName: toolName),
                displayName: "\(server.name): \(toolName.titleCased)",
                defaultPermissionLevel: MCPToolProxy.defaultCapability.defaultPermissionLevel,
                category: .extensions
            )
        })

        let rawInstructions = server.serverInstructions?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = (rawInstructions?.isEmpty == false)
            ? rawInstructions!
            : "Connected MCP server \"\(server.name)\". The server did not provide instructions."

        let toolList = toolNames.isEmpty ? "no tools discovered yet" : toolNames
            .joined(separator: ", ")
        let smallInstruction = "\(instruction) Tools: \(toolList)."

        // MCP metadata varies wildly in length; long instructions degrade the
        // mean-pooled retrieval vector, so the descriptor is capped.
        let descriptor = String(smallInstruction.prefix(500))

        return Skill(
            id: id,
            displayName: server.name,
            description: smallInstruction,
            instruction: instruction,
            smallInstruction: smallInstruction,
            requiredTools: requiredTools,
            requiredCapabilities: [],
            alwaysActive: false,
            customDescriptor: descriptor
        )
    }
}
