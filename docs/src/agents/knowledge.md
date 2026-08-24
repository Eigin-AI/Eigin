# Knowledge

The agent has a unified knowledge base for everything it has learned: a persistent, searchable, structured store about itself, the user, and the world.

It works like memory, not a static store. Used entries stay strong; untouched ones fade. The agent tends it — surfacing what's relevant, retiring what's stale, reconciling contradictions — so the user never has to.

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

All types share relationship fields (`relates_to`, `belongs_to`, `uses`, `describes`, `supersedes`) and can use tags for searchability.

## Tools

| Tool | What it does |
|---|---|
| **Search** | Ranked results by relevance and use (see [Ranking](#ranking)); an empty query returns an overview. |
| **Get** | Full detail for one entry, optionally with expanded relations and chat context. |
| **Add** | Create an entry; schema errors return the expected field structure. |
| **Update** | Merge-update fields on an entry. |
| **Forget** | Hide an entry that no longer holds. Kept, but out of the way. |
| **Supersede** | Replace an old entry with a newer one, recording what replaced what. |
| **Merge** | Fold duplicates into a single entry. |
| **Contest** | Flag entries that contradict each other for the user to settle. |
| **Delete** | Permanently remove an entry (requires consent). |

Forget is the everyday way to retire a memory; delete is the rare, permanent one.

## Ranking

Results rank on relevance plus lightweight signals about how each memory is used:

- **Recency and frequency** — a memory used recently, or used often, ranks ahead of one that's been sitting untouched.
- **Importance** — rare but critical facts (an allergy, say) are protected so they surface when needed, even if they almost never come up.

**Relevance always comes first.** An unrelated memory never outranks a clearly relevant one, no matter how important or frequently used — the signals only decide order among memories that are already a close match. New memories start on neutral footing and earn their standing through use.

## Hydration

The agent doesn't always need to search. Each turn, the [gatekeeper](../conversation/context.md) checks whether the user's message relates to something already in the base, by name mention or semantic similarity, and surfaces a compact summary in per-turn context. 

If the user mentions "Bob" and `actor.bob` exists, the agent sees it without a tool call. Matches are retained for a few turns, so "tell me more about him" still resolves without repeating the name. 

This gives the agent a baseline of relevant knowledge on demand, and it can always use its tools to search for more.

## Chat context

Every entry links to the chat it was created in. `get_knowledge` can optionally return that surrounding chat context, letting the agent recover the conversation behind a piece of knowledge.

## Forgetting

Memories fade by disuse rather than expiring on a set date, and can be retired deliberately. A forgotten memory is hidden from search and ranking but not deleted — the agent can still find it on request. Three things hide a memory: it's forgotten, superseded, or merged into a duplicate.

## Keeping memory tidy

The agent reconciles its own memory, so the user doesn't have to.

| When | What happens |
|---|---|
| **On save** | A new entry close to an existing one triggers a gentle reconcile nudge — supersede, merge, or keep both. A hint only; saving is never blocked. |
| **In the background** | A periodic pass spots likely duplicates, contradictions, and stale low-value entries, and tidies them with the tools above. Genuine contradictions it can't resolve are flagged for the user, and not re-asked. |

Background tidying runs only for agents allowed to act on their own initiative; a purely reactive agent tidies up opportunistically instead.

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
- **Reconcile** (`forget_knowledge`, `supersede_knowledge`, `merge_knowledge`, `contest_knowledge`): default **always**. These hide or reorganise memory but never destroy it.
- **`delete_knowledge`**: default **ask**. Permanent removal requires consent.
