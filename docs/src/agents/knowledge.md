# Knowledge
The agent has a unified knowledge base for everything it has learned — a persistent, searchable, structured store of information about itself, the user, and the world.

Knowledge is built on top of [Firm](https://github.com/42futures/firm), an open-source project by 42futures for building structured knowledge graphs. Each knowledge entry is stored as a `.firm` source file: a small, self-contained text document in Firm's DSL. This makes knowledge both human and machine readable.

## Entity types

Five entity types form the schema:

- **Actor**: a person, AI, or organisation — something that acts
- **Thing**: a physical object, digital tool, place, service, or concept
- **Fact**: a structured truth or claim with explicit provenance (`stated`, `observed`, or `inferred`)
- **Output**: an artefact produced by actors — documents, reports, code, designs
- **Note**: a lightweight highlight worth remembering — the only required field is `content`

All entity types share a common set of relationship fields (`relates_to`, `belongs_to`, `uses`, `describes`) and can carry tags for searchability. Notes are intentionally minimal: the agent can create one with just a content string, no schema knowledge required.

## Tools

Five tools form the agent's interface to knowledge:

- **Search knowledge**: ranked results by semantic similarity and keyword match; no query returns an overview
- **Get knowledge**: full detail for one entry — fields, relationship IDs, optionally expanded related entries and chat context
- **Add knowledge**: create a new entry; schema errors include the expected field structure
- **Update knowledge**: merge-update fields on an existing entry
- **Delete knowledge**: remove an entry (requires user consent)

## Hydration

The agent doesn't always need to search explicitly. Each turn, the [gatekeeper](../conversation/context.md) checks whether the user's message relates to something already in the knowledge base. If it finds matches — by name mention or semantic similarity — it surfaces a compact summary in the per-turn context: entity IDs, primary text, and top relationships.

If the user mentions "Bob" and `actor.bob` exists, the agent sees it immediately without a tool call. Matched entries are retained for a few follow-up turns so the agent doesn't lose context when the user says things like "tell me more about him" without repeating the name.

This is a nudge, not a replacement for the full tools. It covers the common case; the agent can always search, get, or browse for more.

## Embeddings and search

When knowledge is saved or updated, an embedding is computed from the entry's primary content:

| Type | Embedded text |
|---|---|
| actor | `"Name, type"` — e.g. `"Daniel Rothmann, human"` |
| thing | `"Name, category"` — e.g. `"Eigin, digital"` |
| fact | `"Name: claim"` — e.g. `"Eigin privacy: Eigin runs on-device"` |
| output | `"Name: content"` (content truncated) |
| note | content verbatim |

Search scores each entry using `max(embedding_similarity, keyword_score)` and returns results ranked by that score. Keyword matching also uses a prefix-fuzzy strategy (e.g. "privacy" matches "private").

On rebuild, any entries missing embeddings are backfilled automatically.

## Chat context

Any knowledge entry created during a chat carries a `chat_id` link. When retrieving an entry with `get_knowledge`, you can optionally request the surrounding chat context — the messages from that conversation around when the entry was created. This lets the agent recover the full conversational context behind a piece of knowledge.

## Bundled knowledge

The app ships with knowledge about itself: what Eigin is, how it works, what it can do. Bundled entries give the agent baseline knowledge about the application without bloating the system prompt.

Bundled entries are read-only and cannot be modified or deleted.

## Scoping

Knowledge entries can be scoped to [spaces](../conversation/spaces.md):

- **Global** (no space): visible everywhere
- **Space-scoped**: only visible within that space

When the same entity exists in multiple scopes, the most specific version wins — a space-scoped entry shadows its global counterpart. Deleting a space-scoped override reveals the global version again.

Knowledge entries follow space privacy: entries in a private space are never visible from outside that space.

## Permissions

Knowledge tools follow the same [permission model](../tools/permissions.md) as other tools:

- **Read tools** (`search_knowledge`, `get_knowledge`) default to **always**
- **Write tools** (`add_knowledge`, `update_knowledge`) default to **always**
- **`delete_knowledge`** defaults to **ask** — removing knowledge requires user consent
