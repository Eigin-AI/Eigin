# Compaction

Conversations eventually exceed the model's context window. But context limits aren't the only reason to compact. **Context rot** is the bigger problem. As a conversation grows, older messages dilute the agent's attention. The model's responses degrade in quality long before the window is technically full. Compaction keeps the context focused.

## Strategy

The compaction strategy is deliberately aggressive. Very long context conversations drive up inference cost and accelerate context rot. Eigin would rather compact often and keep context lean and focused.

When the threshold is reached, the message history is sent to the model with instructions to produce a summary the conversation can continue from. This summary replaces the older messages. Truncation (dropping oldest messages) is used as a fallback.

