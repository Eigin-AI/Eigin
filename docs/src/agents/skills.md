# Skills

Skills are how the agent gains capabilities. A skill bundles instructions with the tools those instructions need. When a skill is active, its instructions are woven into the system hint and its tools are available for the turn.

## Skill activation

| Kind | When active | Examples |
|---|---|---|
| **Always-active** | Present in every chat from the start | Knowledge, intents, awareness, web search |
| **On-demand** | Enabled by the user or agent when the time is right | Email, scheduling, self-modification |

Some on-demand skills also declare a required [capability](../integrations/README.md) rather than (or in addition to) built-in tools. Email is one: it has no tools of its own and only appears once an integration providing the `email` capability is connected.

## Tool composition

The active skill set is additive. Each active skill contributes its instruction to the system hint and its tools to the turn; the agent can call the union of all active skills' tools.

A skill usually owns a coherent group of tools but can reuse another skill's when its framing calls for it: planning reuses the scheduling skill's calendar and reminder tools. Because the tool set is a union, a shared tool is offered once no matter how many skills require it. Activating a skill takes effect on the next turn.

## Flows

A skill's instruction can lay out a whole multi-step process, but models tend to read it all and try to do everything at once. Flows fix this by drip-feeding the instructions one stage at a time.

A skill declares named flows, each an ordered list of stages. The agent moves through a flow with two tools:

- **`start_flow`**: begins a flow, activating stage one.
- **`advance_flow`**: closes the current stage and returns the next, until the flow ends.

Only the current stage's instructions are shown, so the agent works one step at a time and stays on track even if the conversation drifts.
