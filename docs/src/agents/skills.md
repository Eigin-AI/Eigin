# Skills

Skills are how the agent gains capabilities. A skill bundles a set of instructions with the tools those instructions need. When a skill is active, its instructions are woven into the system prompt and its tools are available for the turn.

## Always-active and on-demand

Some skills are always active, present in every chat from the start. Knowledge, intents, awareness, and web search are examples of always-active skills.

Others are on-demand, enabled by the user or by the agent when the situation calls for them. Email, scheduling, and self-modification are examples of on-demand skills.

## How skills compose

The agent's active skill set is additive. Each active skill contributes its **instruction** to the system prompt and its **tools** to the available tool set for that turn. The union of all active skills' tools is what the agent can call.

Activating a skill takes effect immediately on the next turn.
