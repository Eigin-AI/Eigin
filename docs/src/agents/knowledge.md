# Knowledge

The agent has a unified knowledge base for everything it has learned: a persistent, searchable, structured store about itself, the user, and the world.

Knowledge is built on [Firm](https://github.com/42futures/firm), an open-source tool for structured knowledge graphs. Each entry is a `.firm` source file: a small, self-contained text document in Firm's DSL, so knowledge is both human- and machine-readable.

## Entity types

Five types form the schema:

| Type | What it is |
|---|---|
| **Actor** | A person, AI, or organisation. Something that acts. |
| **Thing** | A physical object, tool, place, service, or concept. |
| **Fact** | A structured truth or claim with provenance. |
| **Output** | An artefact produced by actors: documents, reports, code, designs. |
| **Note** | A small highlight worth remembering. |

All types share relationship fields (`relates_to`, `belongs_to`, `uses`, `describes`) and can use tags for searchability.

## Tools

| Tool | What it does |
|---|---|
| **Search** | Results ranked by semantic similarity and keyword match; an empty query returns an overview. |
| **Get** | Full detail for one entry, optionally with expanded relations and chat context. |
| **Add** | Create an entry; schema errors return the expected field structure. |
| **Update** | Merge-update fields on an entry. |
| **Delete** | Remove an entry (requires consent). |

## Hydration

The agent doesn't always need to search. Each turn, the [gatekeeper](../conversation/context.md) checks whether the user's message relates to something already in the base, by name mention or semantic similarity, and surfaces a compact summary in per-turn context. 

If the user mentions "Bob" and `actor.bob` exists, the agent sees it without a tool call. Matches are retained for a few turns, so "tell me more about him" still resolves without repeating the name. 

This covers gives the agent a baseline of available knowledge on-demand, and it can always use its tools to search for more.

## Chat context

Every entry links to the chat it was created in. `get_knowledge` can optionally return that surrounding chat context, letting the agent recover the conversation behind a piece of knowledge.

## Bundled knowledge

The app ships with read-only knowledge about itself: what Eigin is, how it works, what it can do. This helps the agent correctly answer questions about itself instead of making stuff up.

## Scoping

Entries can be scoped to [spaces](../conversation/spaces.md):

- **Global** (no space): visible everywhere.
- **Space-scoped**: visible within that space.

When an entity exists in multiple scopes, the most specific wins: a space-scoped entry shadows its global counterpart, and deleting the override reveals the global version again. Entries in a private space are never visible from outside it.

## Permissions

- **Read** (`search_knowledge`, `get_knowledge`): default **always**.
- **Write** (`add_knowledge`, `update_knowledge`): default **always**.
- **`delete_knowledge`**: default **ask**. Removing knowledge requires consent.
