# Intents

Intents are the agent's goals: things it is actively trying to do or help with across conversations. The agent sets them itself, based on what it notices the user cares about.

An intent is a short piece of text describing a goal or direction. When the agent picks up on a recurring theme, a need, or something the user is working toward, it sets an intent. When the same topic comes up again, it reinforces it. When a goal is fulfilled or no longer relevant, it resolves or dismisses it.

## Strength and decay

Intents are not permanent. Each intent has a strength that decays over time. To keep an intent active, the agent reinforces it when the topic comes up again. When strength falls below a threshold, the intent becomes inactive and stops influencing the agent's behaviour.

Intents are ordered by strength. When the agent's active intents are surfaced in context, the strongest ones are highlighted first.

## Lifecycle

An intent moves through three states:

- **Active**: influencing the agent, decaying over time
- **Resolved**: the goal was met
- **Dismissed**: the goal is no longer relevant

## Relationship to Initiative

Intents describe what the agent is working toward. [Initiative](./initiative.md) controls how proactively it acts on them.
