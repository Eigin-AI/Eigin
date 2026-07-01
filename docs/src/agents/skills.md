# Skills

Skills are how the agent gains capabilities. A skill bundles a set of instructions with the tools those instructions need. When a skill is active, its instructions are woven into the system prompt and its tools are available for the turn.

## Always-active and on-demand

Some skills are always active, present in every chat from the start. Knowledge, intents, awareness, and web search are examples of always-active skills.

Others are on-demand, enabled by the user or by the agent when the situation calls for them. Email, scheduling, and self-modification are examples of on-demand skills.

## How skills compose

The agent's active skill set is additive. Each active skill contributes its **instruction** to the system prompt and its **tools** to the available tool set for that turn. The union of all active skills' tools is what the agent can call.

A skill usually owns a coherent group of tools, but a skill may reuse tools owned by another skill when its framing calls for them — planning reuses the scheduling skill's calendar and reminder tools. Because the active tool set is a union, a shared tool is offered to the agent exactly once no matter how many active skills require it.

Activating a skill takes effect immediately on the next turn.

## Flows

A skill's instruction can describe a whole multi-step process up front, but models tend to read the whole thing and try to do everything at once instead of working through it turn by turn. Flows fix this by drip-feeding instructions one stage at a time: a skill declares one or more named flows, each an ordered list of stages, and the agent moves through a flow with two tools, `start_flow` and `advance_flow`.

`start_flow` activates a flow's stage-one instructions; from there, each `advance_flow` call closes out the current stage and returns the next one's instructions, until the flow ends. Only the current stage's instructions are ever shown, so the agent's attention stays on the one thing it needs to do next rather than the whole process at once.

Flow state (which flow, which stage, and any notes recorded along the way) persists on the chat, and the active stage's instructions are reinforced every turn via a system hint. This keeps the agent on track even if the conversation drifts, since the reminder doesn't depend on the agent remembering a tool result from several turns back.

A stage can also ask the agent to record a short note when it advances (e.g. what was learned or decided at that stage). Stages configured to show notes get the full accumulated list surfaced alongside their instructions, useful for a closing stage that needs to pull everything gathered so far back together.

The planning skill's `trip`, `shortlist`, `day_out`, and `gathering` flows are the first use of this mechanism. It's meant to generalize: any skill with a multi-step process can define its own flows the same way.
