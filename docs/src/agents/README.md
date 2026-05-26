# Agents

An agent is a persistent AI personality. It carries identity, knowledge, and behaviour into every chat. The aim is a character that grows over time, not a fresh chat window every session.

## The Eigin agent ontology

An Eigin agent is built as a spectrum from **essence** to **capability** - from what the agent *is* to how it *acts*. Each layer rests on the ones below, and each is more changeable than the one beneath.

```mermaid
flowchart TB
    subgraph Spectrum["essence → capability"]
        direction LR
        Core["<b>Core</b><br/>who it is"] --> Experience["<b>Experience</b><br/>chat history"] --> Knowledge["<b>Knowledge</b><br/>what it has learned"] --> Intents["<b>Intents</b><br/>current goals"] --> Skills["<b>Skills</b><br/>how it acts"]
    end

    Initiative["<b>Initiative</b><br/>when it acts"]
    Spectrum -.- Initiative
```

Reading left to right:

1. **[Core](./core.md)** - the agent's essence. Its identity, its view of the user, and the values it operates by, kept as persistent texts injected into every system prompt. The agent's *constitution*: the most fundamental, slowest-changing layer. Change here changes who the agent is.
2. **[Experience](./experience.md)** - what the agent has lived through. The chats it has had with the user, which it can browse, search, and read back. Experience is the raw record everything above is built on.
3. **[Knowledge](./knowledge.md)** - what the agent has learned. A structured graph of actors, things, facts, outputs, and notes, distilled from experience and from the world around the user.
4. **[Intents](./intents.md)** - what the agent is *trying* to do: its goals, the things on its mind. Self-set, built up from what the agent has noticed the user cares about. Intents direct the agent's focus.
5. **[Skills](./skills.md)** - the ways the agent can act on its intents. Bundled instruction and tools, like knowledge, web, scheduling, email. Some skills are always active; others activate on demand.

Sitting alongside this spectrum is **[Initiative](./initiative.md)** - describing how proactively the agent operates. Initiative governs when the rest of the stack runs.

## System prompt assembly

The system prompt is stable across turns - it contains the agent's essence and fundamental context about the Eigin environment. Dynamic context (active skills, intents, interaction mode, space) is injected per-turn via system hints rather than baked into the prompt. See [The gatekeeper](../conversation/context.md).
