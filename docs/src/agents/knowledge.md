# Knowledge

Agents keep structured knowledge about themselves, the user, and the world. They can search it, follow relationships, update entries, and retire stale memories. Read-only bundled entries describe Eigin itself.

The [SDK knowledge API](../sdk/knowledge.md) provides loading, queries, retrieval, and validated edits. Hosts control storage and which entries an agent can access.

## Entity types

Five types form the schema:

| Type | What it is |
|---|---|
| **Actor** | A person, AI, or organisation. Something that acts. |
| **Thing** | A physical object, tool, place, service, or concept. |
| **Fact** | A structured truth or claim with provenance. |
| **Output** | An artefact produced by actors: documents, reports, code, designs. |
| **Note** | A small highlight worth remembering. |

All types share relationship fields (`relates_to`, `belongs_to`, `uses`, `describes`, `supersedes`) and can use tags for searchability.

## Tools

| Tool | What it does |
|---|---|
| **Search** | Find relevant entries or look one up by ID (see [Ranking](#ranking)); an empty query returns an overview. |
| **Get** | Full detail for one entry, optionally with expanded relations and context from its originating chat. |
| **Add** | Create an entry; schema errors return the expected field structure. |
| **Update** | Merge-update fields on an entry. |
| **Forget** | Hide an entry that no longer holds. Kept, but out of the way. |
| **Supersede** | Replace an old entry with a newer one, recording what replaced what. |
| **Merge** | Fold duplicates into a single entry. |
| **Contest** | Flag entries that contradict each other for the user to settle. |
| **Delete** | Permanently remove an entry (requires consent). |

Forget is the everyday way to retire a memory; delete is the rare, permanent one.

## Ranking

Search combines word and meaning matches. Exact IDs prioritize the matching entry; usage and importance can reorder close matches. Opening an entry counts as use; searching leaves its use history unchanged. See [SDK retrieval](../sdk/knowledge.md#find-relevant-entries) for the scoring contract.

## Hydration

Each turn, the [gatekeeper](../conversation/context.md) surfaces compact summaries relevant to the user's message. Mentioning "Bob" can surface `actor.bob` without a tool call. Matches stay in context for a few turns, and the agent can search for more.

## Forgetting

Memories fade by disuse rather than expiring on a set date, and can be retired deliberately. A forgotten memory is hidden from search, ranking, and the knowledge views (graph, list, details) but not deleted — the agent can still find it on request via `include_expired`. Three things hide a memory: it's forgotten, superseded, or merged into a duplicate.

## Keeping memory tidy

The agent reconciles its own memory, so the user doesn't have to.

| When | What happens |
|---|---|
| **On save** | A new entry close to an existing one triggers a gentle reconcile nudge — supersede, merge, or keep both. A hint only; saving is never blocked. |
| **In the background** | A periodic pass spots likely duplicates, contradictions, and stale low-value entries, and tidies them with the tools above. Genuine contradictions it can't resolve are flagged for the user, and not re-asked. |

Background tidying runs only for agents allowed to act on their own initiative; a purely reactive agent tidies up opportunistically instead.

## Scoping

Entries can be scoped to [spaces](../conversation/spaces.md):

- **Global** (no space): visible everywhere.
- **Space-scoped**: visible within that space.

When an entity exists in multiple scopes, the most specific wins: a space-scoped entry shadows its global counterpart, and deleting the override reveals the global version again. Entries in a private space are never visible from outside it.

## Permissions

- **Read** (`search_knowledge`, `get_knowledge`): default **always**.
- **Write** (`add_knowledge`, `update_knowledge`): default **always**.
- **Reconcile** (`forget_knowledge`, `supersede_knowledge`, `merge_knowledge`, `contest_knowledge`): default **always**. These hide or reorganise memory but never destroy it.
- **`delete_knowledge`**: default **ask**. Permanent removal requires consent.
