# The agentic loop

The agentic loop orchestrates the tool-calling cycle:

1. Initiate a request based on a user prompt and chat history
2. Stream the assistant's response from the model
3. If the response contains tool calls, execute each one (checking [permissions](../tools/permissions.md) first)
4. Append tool results and send them back to the model
5. Repeat until the model finishes without requesting tools, or a safety limit is reached

## Safe checkpoints

The loop tracks safe checkpoints so that if it's interrupted for any reason, the chat doesn't end up in a broken state. This matters because inference providers have strict rules about message format, and normalising across multiple providers means being conservative to satisfy the strictest ones.

## Permission gating

Before executing any tool, the loop checks the [permission policy](../tools/permissions.md). Tools can be `always` allowed, `never` allowed (blocked), or require the user to be asked.

This is checked per-call, so the same tool can have different policies in different contexts (e.g. editing core docs is allowed during onboarding, but requires confirmation during normal chat).
