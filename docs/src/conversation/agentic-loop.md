# The agentic loop

The agentic loop orchestrates the tool-calling cycle, exchanging with the model until it produces a reply that needs no more tools.

| Step | What happens |
|---|---|
| **Build request** | Assemble the system prompt, chat history, and the gatekeeper's [system hint](./context.md) into one request. |
| **Stream** | Send it to the [provider](../providers.md) and stream the assistant's response. |
| **Check tool calls** | If the response calls tools, check each against the [permission policy](../tools/permissions.md). |
| **Execute** | Run the allowed calls and append their results. |
| **Repeat** | Send the results back and stream again, until the model replies with no tool calls, or a safety limit is reached. |
| **Reply** | The final response goes to the user. |

## Safe checkpoints

The loop tracks safe checkpoints so an interruption doesn't leave the chat in a broken state. Inference providers have strict message-format rules, and normalising across providers means being conservative enough to satisfy the strictest.

## Permission gating

Before executing any tool, the loop checks the [permission policy](../tools/permissions.md): a tool can be `always` allowed, `never` allowed (blocked), or require asking. This is checked per-call, so the same tool can have different policies in different contexts (e.g. editing core docs is allowed during onboarding but confirmed in normal chat).
