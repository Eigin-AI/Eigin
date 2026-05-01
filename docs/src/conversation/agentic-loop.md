# The agentic loop

The agentic loop orchestrates the tool-calling cycle:

1. Initiate a request based on a user prompt and chat history
2. Stream the assistant's response from the API
3. If the response contains tool calls, execute each one (checking [permissions](../tools/permissions.md) first)
4. Append tool results and send them back to the model
5. Repeat until the model finishes without requesting tools, or a safety limit is reached

**Why a loop?** Many useful agent behaviors require multiple steps: search memories, read the results, decide what to do, take action. A single request-response cycle can't do this. The loop lets the agent chain reasoning steps together autonomously.

## Streaming

Response text is streamed to the UI through a throttler. This gives smooth, character-by-character display without overwhelming the rendering layer.

The throttler is fully drained before tool execution begins, so all prose is visible before the agent takes action.

## Safe checkpoints

The loop tracks "safe checkpoints" to prevent orphaned tool calls — situations where an assistant message contains tool calls but the corresponding results are missing.

The UI sees completed rounds, so the chat is in a valid state even if the loop got interrupted.

## Permission gating

Before executing any tool, the loop checks the [permission policy](../tools/permissions.md). Tools can be `always` allowed, `never` allowed (blocked), or require the user to be asked.

This is checked per-call, so the same tool can have different policies in different contexts (e.g. editing core docs is allowed during bootstrap, but requires confirmation during normal chat).
