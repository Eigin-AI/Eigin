# Initiative
Agents can work proactively for the user, not just respond when spoken to. This is controlled by a **proactivity level** setting with three tiers:

- **Reactive**: the agent only responds when spoken to. No background activity, no [chat hints](../conversation/context.md#hints).
- **Balanced**: the agent occasionally runs in the background and may share thoughts worth hearing. Chat hints are delivered when relevant.
- **Proactive**: the agent regularly reflects and shares observations. Background sessions run more often. Chat hints are delivered when relevant.

## How it works

Background initiative uses the platform's scheduled task system. On each app launch, Eigin registers a background schedule according to the agent's proactivity level. The OS runs the task opportunistically (e.g. while charging).

Two kinds of background session are scheduled at different intervals:

- **Initiative**: the agent reviews its intents, recent chats, and what's been going on, then decides whether there's something worth acting on. If so, it triggers a notification. Tapping the notification opens the app and starts a new chat.
- **Maintenance**: the agent reflects and organises its own context, consolidating knowledge and tidying intents.

During any background session, the agent runs with a restricted tool set. Only tools that don't require user consent are available.

