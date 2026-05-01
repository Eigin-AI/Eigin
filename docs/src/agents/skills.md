# Skills

Skills are how the agent gains capabilities. A skill bundles a set of instructions with the tools those instructions need. When a skill is active, its instructions are woven into the system prompt and its tools are available for the turn.

## Always-active and on-demand

Some skills are always active — present in every chat from the start. Others are on-demand, enabled by the user or by the agent when the situation calls for them.

**Always active**

| Skill | What it enables |
|---|---|
| Knowledge | Saving and recalling information from the knowledge base |
| Intents | Setting, reinforcing, and resolving goals across conversations |
| Awareness | Checking the current time and location |
| Web | Searching the web and fetching page content |

**On-demand**

| Skill | What it enables |
|---|---|
| Self-Modification | Reading and editing core texts, presentation, proactivity, and vocabulary |
| Email | Composing emails via the system mail client |
| Organization | Managing spaces, moving chats, browsing chat history |
| Scheduling | Reading and managing calendar events and reminders |

## How skills compose

The agent's active skill set is additive. Each active skill contributes its **instruction** to the system prompt and its **tools** to the available tool set for that turn. The union of all active skills' tools is what the agent can call.

Activating a skill takes effect immediately on the next turn.
