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

A skill needs all the capabilities it requires: the calendar skill needs `calendar`, the reminders skill needs `reminders`, and the health skill needs `health`. The agent finds such a skill even when it isn't connected: skill search and hints mark it as needing a connection. Activating it is what asks:

1. `activate_skill` waits, and a connect sheet opens over the chat: the integration's own sheet when one provides it, or a list to pick from when several do (email).
2. **Connect, then Continue:** the skill activates and the turn carries on with its tools.
3. **Not now:** the agent is told the person declined, and answers without it.

It asks once. A no (Not now, or removing the integration) is remembered per capability in `DeclinedCapabilities`. After that, activation answers straight away that the person declined, the skill drops out of hints, and the agent says where to connect it instead. Connecting clears the no.

It only asks where someone can answer. In a background turn or from the watch, activation answers at once that connecting needs the user. If iOS has already refused, it says that instead. During a call, the sheet shows only while the call is on screen.
