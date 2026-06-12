# Intents

Intents are the agent's goals: things it is actively trying to do or help with across conversations. The agent sets them itself, based on what it notices the user cares about.

An intent is a short piece of text describing a goal or direction. When the agent picks up on a recurring theme, a need, or something the user is working toward, it sets an intent. It keeps the intent current as things change, and resolves it once the goal is met.

Intents persist until they are explicitly resolved.

## Tasks, events, and schedules

An intent can carry structure that breaks the goal down and ties it to time:

- **Tasks** — a checklist the agent works through. Each task has content, an optional due date and priority, a completion flag, and an optional note on what's blocking it. The agent ticks tasks off as it makes progress.
- **Events** — one-off triggers tied to a fixed date, like a birthday or a deadline. As the event approaches, the intent rises in priority so the agent surfaces it at the right time.
- **Schedules** — recurring triggers: daily, on certain weekdays, or on certain days of the month, with an optional time of day. A schedule lifts the intent around each occurrence — "log sleep every morning", "garden on the weekend".

## Relevance ranking

Intents are ranked by a blended score that reflects how pressing each intent is right now. A schedule firing today or an event a few days out lifts an intent toward the top; intents with open tasks edge ahead of ones that are fully done; and recency keeps freshly-touched intents in view. No single signal dominates outright — the strongest mix wins. When the agent's active intents are surfaced in context, the most relevant appear first, annotated with short cues like "scheduled today" or "in 3 days".

## Lifecycle

An intent moves through three states:

- **Active**: influencing the agent until resolved
- **Resolved**: the goal was met
- **Dismissed**: the goal is no longer relevant

## Relationship to Initiative

Intents describe what the agent is working toward. [Initiative](./initiative.md) controls how proactively it acts on them — and an intent's schedules and events are what make a background session surface a timely reminder.
