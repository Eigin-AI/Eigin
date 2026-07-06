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

The default for capable models, and deliberately aggressive: Eigin compacts early, at about a quarter of the context window, rather than late, since long contexts drive up cost and accelerate rot.

When triggered, everything except the latest user message is sent to the same model to produce a summary, which replaces the older messages as a `<conversation_summary>`. If the history has already blown past the window, the oldest messages are truncated to make the compaction call itself fit; truncation is the last-resort fallback.

## Sliding window

Small on-device models can't afford an extra summarization call, so they compact by dropping the oldest whole messages until the history fits the budget.

The boundary moves with hysteresis: once it advances, it stays put until the conversation grows a good deal further. That keeps the retained prefix stable from turn to turn, so the on-device KV cache is reused instead of re-prefilled every turn.
