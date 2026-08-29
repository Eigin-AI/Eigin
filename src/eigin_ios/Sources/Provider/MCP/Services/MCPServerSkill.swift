import Foundation

/// Projects enabled MCP servers into runtime ``Skill`` values so they flow
/// through the same activation catalog, tool gating, and active-instruction
/// injection as bundled skills — see #140.
///
/// Purely a function of persisted server data: no connection is attempted, so
/// the catalog always lists every enabled server (a disconnected/unreachable
/// server still shows up; the agent discovers connection problems when it
/// tries to activate it — see ``ActivateSkillTool``). `requiredTools` are
/// derived from ``MCPServer/cachedToolNames``, populated the first time a
/// server connects and refreshed on every reconnect. A server that has never
/// connected projects with an empty tool list.
enum MCPServerSkill {
    /// Projects every enabled server into a skill, disambiguating IDs when two
    /// servers sanitize to the same name.
    static func project(servers: [MCPServer]) -> [Skill] {
        var seenIDs: Set<String> = []
        return servers.filter(\.isEnabled).map { server in
            let id = assignID(to: server, disambiguating: &seenIDs)
            return skill(id: id, server: server)
        }
    }

    /// Resolves a single enabled server's projected skill by ID, if any.
    static func skill(forID id: String, servers: [MCPServer]) -> Skill? {
        project(servers: servers).first { $0.id == id }
    }

    /// Resolves the underlying server backing a projected skill ID, if any —
    /// used to connect the right server on activation.
    static func server(forSkillID id: String, servers: [MCPServer]) -> MCPServer? {
        var seenIDs: Set<String> = []
        return servers.filter(\.isEnabled).first { server in
            assignID(to: server, disambiguating: &seenIDs) == id
        }
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
                key: MCPNaming.toolName(serverName: server.name, toolName: toolName),
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

        return Skill(
            id: id,
            displayName: server.name,
            description: smallInstruction,
            instruction: instruction,
            smallInstruction: smallInstruction,
            requiredTools: requiredTools,
            requiredCapabilities: [],
            alwaysActive: false
        )
    }
}
