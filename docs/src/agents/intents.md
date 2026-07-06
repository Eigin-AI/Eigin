# Intents

Intents are the agent's goals: what it's actively trying to do or help with across conversations. The agent sets them itself, from what it notices the user cares about.

An intent is a small data structure describing a goal or direction. The agent sets one when it picks up a specific need, keeps it current as things change, and resolves it once met.

## Tasks, events, and schedules

An intent can carry structure to decompose a goal and tie it to time:

| Structure | What it is | Effect on the intent |
|---|---|---|
| **Tasks** | A checklist the agent works through, each with content, an optional due date and priority, a completion flag, and a blocker note. | Tracks progress toward the goal. |
| **Events** | A one-off trigger on a fixed date, like a birthday or deadline. | Raises priority as the date nears, so it surfaces in time. |
| **Schedules** | A recurring trigger: daily, certain weekdays, or certain days of the month, with an optional time of day. | Lifts the intent around each occurrence ("log sleep every morning"). |

## Relevance ranking

Intents are ranked by how pressing each is right now, blending a few signals:

| Signal | Effect |
|---|---|
| **Timing** | A schedule firing today or an event a few days out lifts an intent. |
| **Open work** | Intents with open tasks edge ahead of fully resolved ones. |
| **Recency** | Freshly-touched intents stay in view. |

No single signal dominates. The most relevant surface first in context, annotated with cues like "scheduled today" or "in 3 days".

## Lifecycle

- **Active**: influencing the agent until resolved.
- **Resolved**: the goal was met.
- **Dismissed**: the goal is no longer relevant.

## Relationship to initiative

Intents describe what the agent is working toward. [Initiative](./initiative.md) controls how proactively it acts on them, and an intent's schedules and events are what make a background session surface a timely reminder.
