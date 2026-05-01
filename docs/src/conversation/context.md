# The gatekeeper

Between the agent and the inference provider sits the **gatekeeper** — a pre/post-processor with two jobs: hydrating each turn with dynamic context, and acting as a safety layer for what goes in and out of the model. Today only context hydration is implemented; the safety seam is in place for what comes next.

A lot of what shapes the agent's next response changes between turns: which skills are active, which intents it's pursuing, the user's interaction mode and language, the active space and its instructions, occasional hints from the app. Baking this into the system prompt would bust the prefix cache; prepending it to persisted user messages would leave stale tags in chat history.

## How it works

The system prompt stays byte-stable across turns — just identity and a brief orientation to Eigin. Each turn the gatekeeper composes the dynamic state into a single `<system_hint>` block and appends it to the latest user message **at API call time only**. The persisted message is never modified.

Each section of the block is produced by a small source. Most are stateless; a few hold session state — the interaction-mode source, for example, emits the full description only on the first turn or when the mode changes.

## Interaction modes

- **Text** — full formatting, markdown, lists, code blocks
- **Dictation** — the user is speaking; infer intent through transcription noise
- **Live call** — half-duplex voice; keep replies short and speech-friendly

## Knowledge hydration

Each turn, the gatekeeper checks whether the user's message relates to something already in the agent's [knowledge base](../agents/knowledge.md). If it finds matches, a compact summary appears in the hint block — entity IDs, primary text, and top relationships — framed as a starting point, not a definitive answer.

Matching works by scanning actors, things, and facts for name mentions in the user's message, and by running a broader knowledge search for semantic and keyword similarity. The top three results surface. Matches are retained for a few turns so the agent doesn't lose context when the user's follow-up messages don't repeat the name ("yes, tell me more about him").

The agent can always search or retrieve full details with its tools — hydration just gives it a head start.

## Hints

The app occasionally nudges the agent — "it's been a while since you revisited the user core", "capture knowledge from this conversation", "compaction is approaching". A hint shows whenever its condition is satisfied and its per-hint cooldown has elapsed. Delivery is gated by the agent's [proactivity level](../agents/initiative.md): reactive agents never receive hints; balanced and proactive agents do.

## Safety

The gatekeeper's second job — filtering or detecting dangerous inputs before they reach the model, screening outputs before they reach the user, and delegating flagged content to dedicated subsystems — is not implemented yet. The seam is the reason the gatekeeper is a standalone component rather than inlined into the pipeline.
