#if DEBUG
import Foundation
import SwiftData

// MARK: - Transfer Structs

struct AgentTransfer: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var identityCore: String
    var userCore: String
    var soulCore: String
    var providerID: UUID
    var model: String
    var voiceIdentifier: String?
    var proactivityRaw: Int
    var bootstrapComplete: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct ChatTransfer: Codable {
    var id: UUID
    var agentID: UUID
    var spaceID: UUID?
    var title: String
    var titleOrigin: String?
    var createdAt: Date
    var updatedAt: Date
    var needsCompaction: Bool
}

struct MessageTransfer: Codable {
    var id: UUID
    var chatID: UUID?
    var role: String
    var content: String
    var toolCallID: String?
    var toolCallsBase64: String?
    var isCompactionSummary: Bool
    var timestamp: Date
}

struct SpaceTransfer: Codable {
    var id: UUID
    var agentID: UUID
    var name: String
    var emoji: String
    var instructions: String
    var bootstrapComplete: Bool
    var isPrivate: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct FirmSourceTransfer: Codable {
    var id: UUID
    var path: String
    var content: String
    var spaceID: UUID?
    var agentID: UUID?
    var chatID: UUID?
    var embedding: [Double]?
    var createdAt: Date
    var updatedAt: Date
    // Memory signals (SchemaV8). Optional so older exports still decode.
    var accessCount: Double?
    var lastAccessedAt: Date?
    var importance: Double?
    var expired: Bool?
    var contested: Bool?
    var lastReviewedAt: Date?
}

struct ProviderTransfer: Codable {
    var id: UUID
    var name: String
    var baseURL: String
    var availableModels: [String]
    var enabledModels: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct AgentToolGrantTransfer: Codable {
    var id: UUID
    var agentID: UUID
    var kind: String
    var key: String
    var level: String
}

struct ChatToolGrantTransfer: Codable {
    var id: UUID
    var chatID: UUID
    var kind: String
    var key: String
}

// MARK: - Export Package

struct DataExportPackage: Codable {
    var version: Int = 1
    var exportedAt: Date
    var providers: [ProviderTransfer]
    var agents: [AgentTransfer]
    var chats: [ChatTransfer]
    var messages: [MessageTransfer]
    var spaces: [SpaceTransfer]
    var firmSources: [FirmSourceTransfer]
    var agentToolGrants: [AgentToolGrantTransfer]
    var chatToolGrants: [ChatToolGrantTransfer]
}

// MARK: - Service

enum DataExportService {
    static func export(context: ModelContext) throws -> URL {
        let providers = try context.fetch(FetchDescriptor<Provider>())
        let agents = try context.fetch(FetchDescriptor<Agent>())
        let chats = try context.fetch(FetchDescriptor<Chat>())
        let messages = try context.fetch(FetchDescriptor<Message>())
        let spaces = try context.fetch(FetchDescriptor<Space>())
        let firmSources = try context.fetch(FetchDescriptor<FirmSource>())
        let agentGrants = try context.fetch(FetchDescriptor<AgentToolGrant>())
        let chatGrants = try context.fetch(FetchDescriptor<ChatToolGrant>())

        let package = DataExportPackage(
            exportedAt: .now,
            providers: providers.map { p in
                ProviderTransfer(
                    id: p.id, name: p.name, baseURL: p.baseURL,
                    availableModels: p.availableModels,
                    enabledModels: p.enabledModels,
                    createdAt: p.createdAt, updatedAt: p.updatedAt
                )
            },
            agents: agents.map { a in
                AgentTransfer(
                    id: a.id, name: a.name, emoji: a.emoji,
                    identityCore: a.identityCore, userCore: a.userCore, soulCore: a.soulCore,
                    providerID: a.providerID, model: a.model,
                    voiceIdentifier: a.voiceIdentifier,
                    proactivityRaw: a.proactivity.rawValue,
                    bootstrapComplete: a.bootstrapComplete,
                    createdAt: a.createdAt, updatedAt: a.updatedAt
                )
            },
            chats: chats.map { c in
                ChatTransfer(
                    id: c.id, agentID: c.agentID, spaceID: c.spaceID,
                    title: c.title, titleOrigin: c.titleOrigin.rawValue,
                    createdAt: c.createdAt, updatedAt: c.updatedAt,
                    needsCompaction: c.needsCompaction
                )
            },
            messages: messages.map { m in
                MessageTransfer(
                    id: m.id, chatID: m.chat?.id,
                    role: m.role, content: m.content,
                    toolCallID: m.toolCallID,
                    toolCallsBase64: m.toolCallsData.map { $0.base64EncodedString() },
                    isCompactionSummary: m.isCompactionSummary,
                    timestamp: m.timestamp
                )
            },
            spaces: spaces.map { s in
                SpaceTransfer(
                    id: s.id, agentID: s.agentID,
                    name: s.name, emoji: s.emoji,
                    instructions: s.instructions,
                    bootstrapComplete: s.bootstrapComplete,
                    isPrivate: s.isPrivate,
                    createdAt: s.createdAt, updatedAt: s.updatedAt
                )
            },
            firmSources: firmSources.map { f in
                FirmSourceTransfer(
                    id: f.id, path: f.path, content: f.content,
                    spaceID: f.spaceID, agentID: f.agentID,
                    chatID: f.chatID, embedding: f.embedding,
                    createdAt: f.createdAt, updatedAt: f.updatedAt,
                    accessCount: f.accessCount, lastAccessedAt: f.lastAccessedAt,
                    importance: f.importance, expired: f.expired,
                    contested: f.contested, lastReviewedAt: f.lastReviewedAt
                )
            },
            agentToolGrants: agentGrants.map { g in
                AgentToolGrantTransfer(
                    id: g.id, agentID: g.agentID,
                    kind: g.kind.rawValue, key: g.key, level: g.level.rawValue
                )
            },
            chatToolGrants: chatGrants.map { g in
                ChatToolGrantTransfer(
                    id: g.id, chatID: g.chatID,
                    kind: g.kind.rawValue, key: g.key
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "eigin_export_\(formatter.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    static func importData(from url: URL, context: ModelContext) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(DataExportPackage.self, from: data)

        // Delete existing data (chats first for cascade to messages)
        try context.delete(model: Chat.self)
        try context.delete(model: Message.self)
        try context.delete(model: FirmSource.self)
        try context.delete(model: AgentToolGrant.self)
        try context.delete(model: ChatToolGrant.self)
        try context.delete(model: Space.self)
        try context.delete(model: Agent.self)
        try context.delete(model: Provider.self)
        try context.save()

        // Insert providers (API keys live in Keychain, not here)
        for p in package.providers {
            let provider = Provider(name: p.name, baseURL: p.baseURL)
            provider.id = p.id
            provider.availableModels = p.availableModels
            provider.enabledModels = p.enabledModels
            provider.createdAt = p.createdAt
            provider.updatedAt = p.updatedAt
            context.insert(provider)
        }

        // Insert agents
        for a in package.agents {
            let agent = Agent(name: a.name, providerID: a.providerID, model: a.model)
            agent.id = a.id
            agent.emoji = a.emoji
            agent.identityCore = a.identityCore
            agent.userCore = a.userCore
            agent.soulCore = a.soulCore
            agent.voiceIdentifier = a.voiceIdentifier
            agent.proactivity = ProactivityLevel(rawValue: a.proactivityRaw) ?? .reactive
            agent.bootstrapComplete = a.bootstrapComplete
            agent.createdAt = a.createdAt
            agent.updatedAt = a.updatedAt
            context.insert(agent)
        }

        // Insert spaces
        for s in package.spaces {
            let space = Space(agentID: s.agentID)
            space.id = s.id
            space.name = s.name
            space.emoji = s.emoji
            space.instructions = s.instructions
            space.bootstrapComplete = s.bootstrapComplete
            space.isPrivate = s.isPrivate
            space.createdAt = s.createdAt
            space.updatedAt = s.updatedAt
            context.insert(space)
        }

        // Insert chats and build lookup
        var chatLookup: [UUID: Chat] = [:]
        for c in package.chats {
            let chat = Chat(agentID: c.agentID, spaceID: c.spaceID, title: c.title)
            chat.id = c.id
            if let raw = c.titleOrigin, let origin = TitleOrigin(rawValue: raw) {
                chat.titleOrigin = origin
            }
            chat.createdAt = c.createdAt
            chat.updatedAt = c.updatedAt
            chat.needsCompaction = c.needsCompaction
            context.insert(chat)
            chatLookup[c.id] = chat
        }

        // Insert messages
        for m in package.messages {
            let toolCallsData: Data? = m.toolCallsBase64.flatMap { Data(base64Encoded: $0) }
            let message = Message(
                role: m.role,
                content: m.content,
                toolCallID: m.toolCallID,
                toolCallsData: toolCallsData
            )
            message.id = m.id
            message.isCompactionSummary = m.isCompactionSummary
            message.timestamp = m.timestamp
            if let chatID = m.chatID {
                message.chat = chatLookup[chatID]
            }
            context.insert(message)
        }

        // Insert firm sources (knowledge entries)
        for f in package.firmSources {
            let source = FirmSource(
                path: f.path,
                content: f.content,
                spaceID: f.spaceID,
                agentID: f.agentID,
                chatID: f.chatID
            )
            source.id = f.id
            source.embedding = f.embedding
            source.createdAt = f.createdAt
            source.updatedAt = f.updatedAt
            source.accessCount = f.accessCount ?? 0
            source.lastAccessedAt = f.lastAccessedAt
            source.importance = f.importance ?? 0.5
            source.expired = f.expired ?? false
            source.contested = f.contested ?? false
            source.lastReviewedAt = f.lastReviewedAt
            context.insert(source)
        }

        // Insert agent tool grants
        for g in package.agentToolGrants {
            let capability = ToolCapability(
                kind: GrantKind(rawValue: g.kind) ?? .builtIn,
                key: g.key,
                displayName: g.key,
                defaultPermissionLevel: .ask,
                category: .external
            )
            let grant = AgentToolGrant(
                agentID: g.agentID,
                capability: capability,
                level: ToolPermissionLevel(rawValue: g.level) ?? .ask
            )
            grant.id = g.id
            context.insert(grant)
        }

        // Insert chat tool grants
        for g in package.chatToolGrants {
            let capability = ToolCapability(
                kind: GrantKind(rawValue: g.kind) ?? .builtIn,
                key: g.key,
                displayName: g.key,
                defaultPermissionLevel: .ask,
                category: .external
            )
            let grant = ChatToolGrant(
                chatID: g.chatID,
                capability: capability
            )
            grant.id = g.id
            context.insert(grant)
        }

        try context.save()
    }
}
#endif
