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

Background sessions use only tools with effective **Always allow** permission. Tools set to **Ask** or **Never** are unavailable.

Notifications arrive at the next sensible local time unless the agent chooses an explicit future delivery time to match the user's wishes.

## Skills and connections

Initiative runs can search for and activate skills to check current information from configured integrations and MCP servers.

| Rule | Behavior |
|---|---|
| Lifetime | Activation lasts for one initiative run and does not change chat skills |
| Instructions | Activation returns the skill’s instructions; its authorized tools become available on the next model round |
| Permissions | Activation grants no permissions; each tool still needs **Always allow** |
| Reconnection | Existing credentials may be used or refreshed silently |
| Missing access | Missing setup, credentials, or sign-in makes the integration unavailable; no permission or connection UI opens |
| Platform access | Platform integrations need full OS authorization for background use; partial access makes that integration unavailable |
| Optional connections | Unavailable optional integrations are omitted; the skill can still activate |

## Requested follow-ups

A follow-up delivers a prepared message as a local notification. Opening it starts a new conversation with the message and a self-contained briefing. Delivery uses the saved content without another model run.

| Context | Tool | Approval | Delivery time |
|---|---|---|---|
| Regular and small-context chat | `follow_up` | **Ask** by default; normal agent and chat grants apply | A future time is required |
| Background initiative | `background_notify` | Always allowed within background runs | Explicit future time, or the next sensible local daytime slot |

- Requested follow-ups work at every proactivity level, including **Reactive**.
- On first approved use in a foreground chat, Eigin asks for iOS notification authorization if it has not been requested. Background runs cannot display this prompt.
- Denied notification authorization returns an actionable error. Enable notifications in iOS Settings before retrying.
- The chat tool reports success after iOS accepts the notification request. Background tools acknowledge queueing for the background runner. System settings and Focus modes control presentation.
- If an explicit delivery time elapses before scheduling, choose a new future time and retry.
- Use follow-ups for one-off pings, Reminders for tracked tasks, and Calendar for events.
