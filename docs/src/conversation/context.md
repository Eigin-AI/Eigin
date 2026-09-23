# The gatekeeper

Between the agent and the inference provider sits the **gatekeeper**: a pre/post-processor that hydrates each turn with dynamic context. It's a seam built to grow.

Much of what shapes the next response changes between turns: active skills, intents, interaction mode, the active space, occasional hints. Baking that into the system prompt would bust the prefix cache; prepending it to persisted messages would leave stale tags in history. The gatekeeper solves both.

## How it works

The system prompt stays byte-stable across turns: just identity and a brief orientation. Each turn, the gatekeeper composes the dynamic state into a single `<system_hint>` block and appends it to the latest user message at inference time only, never touching the persisted message.

Each part of the block comes from a small **source**. Most are stateless; a few hold session state (the interaction-mode source, for one, sends its full description only on the first turn or when the mode changes). Small-context models get a reduced set.

## System hint sources

| Source | What it adds |
|---|---|
| **General info** | Time, date, and model info. |
| **Language** | The user's current language. |
| **Interaction mode** | How the user is interacting (see below). |
| **Space** | The active [space](./spaces.md) and its instructions. |
| **Active skills** | Instructions for the skills active this turn. |
| **Available skills** | Skills the agent can activate on demand. |
| **Active flow** | The current [flow](../agents/skills.md#flows) stage's instructions. |
| **Active intents** | The agent's most relevant [intents](../agents/intents.md). |
| **Relevant knowledge** | A compact summary of [knowledge](../agents/knowledge.md) matching the message. |
| **Seasonal** | A sense of the time of year, to speak into holidays and breaks. |
| **Hints** | App [nudges](../agents/initiative.md) worth acting on, when relevant. |

## Interaction modes

| Mode | Reply style |
|---|---|
| **Text** | Full formatting: markdown, lists, code blocks. |
| **Dictation** | The user is speaking; infer intent through transcription noise. |
| **Live call** | Half-duplex voice; keep replies short and speech-friendly. |
| **Headless** | Voice from a small device like Apple Watch; one or two plain, speakable sentences. |
