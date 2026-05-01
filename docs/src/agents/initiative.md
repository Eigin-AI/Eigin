# Initiative
Agents can work proactively for the user, not just respond when spoken to. This is controlled by a **proactivity level** setting with three tiers:

- **Reactive**: the agent only responds when spoken to. No background activity, no [chat hints](../conversation/context.md#hints).
- **Balanced**: the agent occasionally runs in the background and may share thoughts worth hearing. Chat hints are delivered when relevant.
- **Proactive**: the agent regularly reflects and shares observations. Background sessions run more often. Chat hints are delivered when relevant.

## How it works
Background initiative uses the platform's scheduled task system. On each app launch, Eigin registers a background schedule according to the agent's proactivity level. The OS runs the task opportunistically (e.g. while charging).

During a background session, the agent runs with a restricted tool set. Only tools that don't require user consent are available. If the agent decides something is worth sharing, it triggers a notification. Tapping the notification opens the app and navigates to a new chat.

## Why initiative matters
A reactive agent is a tool you pick up and put down. A proactive agent is a collaborator that thinks about your work even when you're not around. 

It can notice patterns in your schedule, remind you of commitments, or surface observations from its accumulated [knowledge](./knowledge.md) without being asked.
