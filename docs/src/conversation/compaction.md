# Compaction

Conversations eventually outgrow the model's context window, but the window limit isn't the main worry.

## The problem is context rot
As history grows, older messages dilute the agent's attention and reply quality drops long before the window is full. Long contexts also cost more per turn. Compaction keeps the working context lean and focused.

How Eigin compacts depends on the model:

| Strategy | Used for | How it works |
|---|---|---|
| **Summarization** | Capable, large-context models | An LLM call condenses older messages into a summary the conversation continues from. |
| **Sliding window** | Small-context, on-device models | The oldest whole messages are dropped, no summary. |

## Summarization

The default for capable models, and deliberately aggressive: compaction fires at about a quarter of the context window, since long contexts cost more and rot attention earlier.

The summary is produced in-conversation: Eigin appends a synthetic user message to the turn's payload asking the model to summarize everything above it — most recent turns excepted — in a fixed template, inside `<conversation_summary>` tags. The request continues the payload just served, so the provider's prompt cache covers almost all of it; the reply becomes the summary.

The most recent turns stay verbatim after the summary: at least two whole turns, extended while they fit a small fraction of the window. The conversation resumes from `[summary, recent turns verbatim]`. The divider marks where compaction fired; nothing is hidden from the user.

If the summarise request wouldn't fit the model's window, the oldest covered messages are truncated first. Last resort.

## Sliding window

Small on-device models can't afford an extra summarization call, so they compact by dropping the oldest whole messages until the history fits the budget.

The boundary moves with hysteresis: once it advances, it stays put until the conversation grows a good deal further. That keeps the retained prefix stable from turn to turn, so the on-device KV cache is reused instead of re-prefilled every turn.
