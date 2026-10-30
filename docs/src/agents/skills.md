# Skills

Skills are how the agent gains capabilities. A skill bundles instructions with the tools those instructions need. When a skill is active, its instructions are woven into the system hint and its tools are available for the turn.

## Skill activation

| Kind | When active | Examples |
|---|---|---|
| **Always-active** | Present in every chat from the start | Knowledge, intents, awareness, web search |
| **On-demand** | Activated by the agent when it needs it: it's hinted about relevant skills and can search the catalog for more | Email, calendar, reminders, self-modification |

Some on-demand skills also declare a required [capability](../integrations/README.md) rather than (or in addition to) built-in tools. Email is one: it has no tools of its own and only appears once an integration providing the `email` capability is connected.

## Tool composition

The active skill set is additive. Each active skill contributes its instruction to the system hint and its tools to the turn; the agent can call the union of all active skills' tools.

A skill usually owns a coherent group of tools but can reuse another skill's when its framing calls for it: planning reuses the calendar skill's calendar tools and the reminders skill's reminder tools. Because the tool set is a union, a shared tool is offered once no matter how many skills require it. Newly activated tools become available on the next model round, including within the current turn.

A skill needs all the capabilities it requires — its instructions describe tools each one provides, so it only advertises when every one of them is connected. Capabilities that improve it without being necessary are optional: planning takes calendar and reminders as optional, working with whatever is connected and never asking.

## Flows

A skill's instruction can lay out a whole multi-step process, but models tend to read it all and try to do everything at once. Flows fix this by drip-feeding the instructions one stage at a time.

A skill declares named flows, each an ordered list of stages. The agent moves through a flow with two tools:

- **`start_flow`**: begins a flow, activating stage one.
- **`advance_flow`**: closes the current stage and returns the next, until the flow ends.

Only the current stage's instructions are shown, so the agent works one step at a time and stays on track even if the conversation drifts.
