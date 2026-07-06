# Initiative

Agents can work proactively, not just respond when spoken to. A **proactivity level** setting has three tiers:

| Level | Background activity |
|---|---|
| **Reactive** | None; responds only when spoken to |
| **Balanced** | Occasional; may share thoughts worth hearing |
| **Proactive** | Frequent; regularly reflects and shares observations |

## How it works

Background initiative uses the platform's scheduled task system. On each app launch, Eigin registers a background schedule matching the proactivity level; the OS runs it opportunistically (e.g. while charging).

Different kinds of background session run at different intervals:

| Session | What it does |
|---|---|
| **Initiative** | Reviews intents, recent chats, and what's been going on, then decides whether anything is worth acting on. Triggers a notification if so. |
| **Maintenance** | Reflects and organises the agent's own context, consolidating knowledge and tidying intents. |

During any background session the agent runs with a restricted tool set that don't require user consent.
