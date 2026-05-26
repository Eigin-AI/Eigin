# The gatekeeper

Between the agent and the inference provider sits the **gatekeeper**: a pre/post-processor responsible for hydrating each turn with dynamic context. It is designed to be extended with more pre- and post-processing over time.

A lot of what shapes the agent's next response changes between turns: which skills are active, which intents it's pursuing, the user's interaction mode and language, the active space and its instructions, occasional hints from the app. Baking this into the system prompt would bust the prefix cache; prepending it to persisted user messages would leave stale tags in chat history.

## How it works

The system prompt stays byte-stable across turns: just identity and a brief orientation to Eigin. Each turn the gatekeeper composes the dynamic state into a single `<system_hint>` block and appends it to the latest user message at inference time only. The persisted message is never modified.

Each section of the block is produced by a small source. Most are stateless; a few hold session state. The interaction mode source, for example, emits the full description only on the first turn or when the mode changes.

## Interaction modes

The current interaction mode is injected each turn:

- **Text**: full formatting, markdown, lists, code blocks
- **Dictation**: the user is speaking; infer intent through transcription noise
- **Live call**: half-duplex voice; keep replies short and speech-friendly

## Knowledge hydration

Each turn, the gatekeeper searches for [knowledge](../agents/knowledge.md) related to the user's message. If anything relevant surfaces, a compact summary is included in the hint block as a starting point for the agent.

## Hints

Hints are nudges from the app to the agent: things worth thinking about or acting on that aid the user journey. Hint delivery is gated by the agent's [proactivity level](../agents/initiative.md). Reactive agents never receive hints; balanced and proactive agents do.

## What's next

The gatekeeper is a natural place to add filtering of dangerous inputs before they reach the model, and screening of outputs before they reach the user. There are many ideas here - it's a seam designed to grow.
