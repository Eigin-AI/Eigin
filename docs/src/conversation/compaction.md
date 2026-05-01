# Compaction

Conversations eventually exceed the model's context window. But context limits aren't the only reason to compact — **context rot** is the bigger problem. As a conversation grows, older messages dilute the agent's attention. The model's responses degrade in quality long before the window is technically full. Compaction keeps the context focused.

## Strategy

The compaction strategy is relatively aggressive (triggers around 25% of the context window). When the threshold is reached, the message history is sent to the model with instructions to produce a summary that the conversation can continue from. This summary replaces the older messages. Truncation (dropping oldest messages) is used as a fallback.

Token estimation uses conservative character-based heuristics (~4 chars per token) that intentionally overestimate by ~20%. This triggers compaction before hitting actual provider limits to avoid broken chats.

In text chat, a progress indicator is shown during compaction. In [live calls](../voice/live-call.md), compaction happens silently.
