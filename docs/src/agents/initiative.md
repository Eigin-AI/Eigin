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
