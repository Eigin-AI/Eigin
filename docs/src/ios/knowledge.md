# Knowledge on iOS

The knowledge graph is backed by [Firm](https://firm.42futures.com) — a plain-text DSL for structured knowledge. Each entity in the graph is stored as a `.firm` text file. On iOS, that content is persisted as a `FirmSource` SwiftData model — a record with a path, the raw `.firm` content string, optional scope IDs (agent, space, chat), and an embedding vector for semantic search.

`DefaultKnowledgeService` wraps a `FirmSession` (the Firm engine). On `rebuild()`, it loads all `FirmSource` records visible to the current agent/space scope, feeds their content into the session, and produces a queryable graph. Queries return typed entities and their relationships.

## Embeddings

Each `FirmSource` carries an `embedding: [Double]?` — a vector computed on-device when the source is created or updated. The knowledge service uses this for semantic search alongside keyword matching (hybrid search).

## Scoping

Sources scope at three levels: global (no agentID/spaceID), agent-specific, or space-specific. The service picks the most specific source when there are overlapping paths, so a space can override a global default.

## Hydration

Per-turn knowledge hydration runs inside the gatekeeper as `RelevantKnowledgeSource`. Two passes find relevant entries:

1. **Name mention** — tokenises the user message and each actor/thing/fact entity's text, then checks for whole-word overlap. Case-insensitive, language-agnostic (works in English and Danish equally). Handled by `KnowledgeHydrator`.
2. **KB search** — runs the message through `KnowledgeSearchEngine`, the same hybrid scoring (embedding similarity + keyword match) that the agent's `search_knowledge` tool uses.

Results merge, deduplicate, and the top 3 render with their relationships into the `<system_hint>` block. The source retains matches for a few turns so follow-up messages that don't re-mention the entity still have context.

`KnowledgeSearchEngine` is a shared scoring primitive extracted from `SearchKnowledgeTool`, `KnowledgeAutoLinker`, and the link-suggestion helpers.

## Critical files

- `src/eigin_ios/Sources/Core/Persistence/SchemaVersions/SchemaV1/SchemaV1+FirmSource.swift` — the `@Model`
- `src/eigin_ios/Sources/Agent/Knowledge/Services/KnowledgeService.swift` — protocol + `DefaultKnowledgeService`
- `src/eigin_ios/Sources/Agent/Knowledge/Services/KnowledgeSearchEngine.swift` — shared scoring primitive (keyword + embedding hybrid)
- `src/eigin_ios/Sources/Agent/Knowledge/Services/FirmFFI.swift` — Swift bridge to the Firm engine
- `src/eigin_ios/Sources/Chat/Services/Gatekeeper/KnowledgeHydrator.swift` — per-turn hydration logic
- `src/eigin_ios/Sources/Chat/Services/Gatekeeper/Sources/RelevantKnowledgeSource.swift` — gatekeeper source
