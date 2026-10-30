# Platform integrations

Platform integrations are the ones iOS gives permission for, rather than an account: **Apple Health**, **Apple Calendar**, **Apple Reminders** and **Location**. They're listed, added and removed like any other integration, under **On this phone** in the catalogue. The app labels them "On this phone"; in code they're `platform` (the `.platform` auth kind).

| Integration | Capability | Eigin reads | Eigin saves | Permission lives in |
|---|---|---|---|---|
| Apple Health | `health` | Activity, sleep, nutrition, body measurements, heart | Meals, sleep, body measurements | Apple Health |
| Apple Calendar | `calendar` | Events | Events | Settings |
| Apple Reminders | `reminders` | Reminders | Reminders | Settings |
| Location | `location` | Location, while Eigin is open | — | Settings |

## Connecting

Connecting shows what Eigin will read and save before iOS asks, because the system prompt names the data but not why. Continue then shows the iOS prompt (Apple Health shows its own). There are no credentials: a connection is an `Integration` row recording the capability.

iOS asks once. If it has already refused, the sheet says so and links to where it can be changed, instead of asking again.

## What the app can see

iOS keeps the permission, and Eigin can't take it back, so the detail screen separates the two:

- **Not allowed** marks a kind of data iOS reports as off. A footnote and the "Change access in …" link lead to Settings, where access is changed.
- **Not asked yet** shows when the integration is connected but iOS has never been asked for the access Eigin needs, e.g. it changed since the person last allowed it. Tools can't ask, so the screen offers to.
- **Apple Health never says what it lets Eigin read.** It only reports what Eigin may save, so only saves can show as Not allowed. A person who allowed nothing still reads as connected; the health skill treats an empty read as "check access", not as zero.
- **Calendars can be shared add-only.** Eigin can then save events but not see them, so creating an event still works and reading doesn't.

There are no per-kind switches. To narrow what the agent does, use the tool permissions in Agent → Permissions.

**Remove** stops Eigin using it and records a no (see below). It doesn't change what iOS allows.

## Tools

Health, calendar and reminder tools are built only for a connected integration, and they never prompt iOS themselves. Lost access after connecting is not a disconnect: the tool returns a plain error saying it isn't allowed in Settings.

Location has no tools of its own. The awareness tools (time and place, weather, places, directions) use it when it's connected and allowed, and work without it otherwise. No skill requires it, so a chat never asks to connect it. The first time iOS allows location, the Location integration is recorded as connected so it shows in Connections. Removing it stops Eigin using location without asking again.

## Connecting from a chat

Skills require capabilities such as `calendar`, `reminders`, or `health`. Search and hints identify skills that need a connection.

1. First activation returns `confirmation_required`, prompting the agent to explain the connection and ask permission.
2. After a later user reply, a matching retry opens the connection sheet. The agent interprets consent.
3. **Connect, then Continue:** activates the skill. **Not now:** records a decline and the agent answers without it.

Pending requests live in memory, scoped to the conversation, skill, and missing capabilities. Text and live voice share this flow. Cancellation or incomplete connection requires a fresh handshake on a later turn. Already-connected skills activate immediately.

`DeclinedCapabilities` remembers **Not now** and removed connections per capability. Declined skills drop out of hints; connecting clears the decline.

Connection sheets require an interactive foreground chat or visible call. Background and watch turns report that the user must connect separately. iOS refusals direct the user to Settings.
