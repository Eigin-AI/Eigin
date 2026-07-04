/// Static .firm source strings bundled with the app.
///
/// These define the knowledge-base ontology (schemas) and any seed entities
/// that ship with the app. Loaded into every ``KnowledgeService`` session before
/// user/agent-created content.
///
/// Each entity has its own source entry (one entity per file) so that
/// every source — bundled or user-created — maps to exactly one entity.
///
/// The schemas and seed entities live as `.firm` sources in the `design/knowledge`
/// firm workspace and are compiled into ``BundledKnowledgeRegistry`` at
/// `just generate`. Edit those sources, not the generated registry.
enum BundledKnowledge {
    // MARK: - Well-Known Entity IDs

    /// The agent's own actor entity in the knowledge graph.
    static let agentActorID = "actor.agent"
    /// The user's actor entity in the knowledge graph.
    static let userActorID = "actor.user"
    /// The Eigin app entity in the knowledge graph.
    static let eiginThingID = "thing.eigin"

    // MARK: - Bundled Content

    /// The knowledge-base ontology, from `design/knowledge/schemas.firm`.
    static let schemas = BundledKnowledgeRegistry.schemas

    /// Seed entities, one per `design/knowledge/<type>/<id>.firm` source.
    private static let seedEntities = BundledKnowledgeRegistry.seedEntities

    // MARK: - Virtual paths

    /// Path prefix for bundled (read-only) content.
    static let bundledPrefix = "bundled/"

    /// Path prefix for user/agent-created content.
    static let knowledgePrefix = "knowledge/"

    /// Build the virtual path for a single entity source.
    static func entityPath(prefix: String, type: String, id: String) -> String {
        "\(prefix)\(type)/\(id).firm"
    }

    /// All bundled sources: schemas + one source per seed entity.
    static let allSources: [(path: String, content: String)] = {
        var sources: [(path: String, content: String)] = [
            (path: "\(bundledPrefix)schemas.firm", content: schemas),
        ]
        for entity in seedEntities {
            sources.append(
                (
                    path: entityPath(prefix: bundledPrefix, type: entity.type, id: entity.id),
                    content: entity.content
                )
            )
        }
        return sources
    }()
}
