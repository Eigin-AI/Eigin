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

## Silent and interrupted turns

An empty final reply or recoverable cloud-stream interruption gets one automatic continuation per turn. A request-only system hint asks the model to finish using existing results. Cancellation, limits, refusals, and explicit background completion do not trigger recovery.

Repeated silence shows a tappable continuation card. The credits-ready card offers the same action: resume saved work without resending the user's message.

## Safe checkpoints

The SDK builds checkpoint snapshots from recorded output and host progress facts. Completed tool results and eligible partial prose are retained. Outstanding cloud tool calls receive uncertainty results, so continuation can check their state before repeating them. Completed local inline exchanges are retained as recorded.

### SDK usage

1. Collect message values from `Experimental.Agent.Round` and track the safe-to-retain prefix after each assistant batch, tool result, or inline exchange.
2. Call `Experimental.Agent.checkpoint(_:progress:)` with that snapshot, completion and execution state, partial prose, and the current prose message's position if already recorded.
3. Restore app identities from output provenance: `.produced(index:)` retains the source identity, `.partialProse` uses the streaming identity, and `.interruptedTool` receives a new identity.
4. Save the chosen snapshot once, then settle host turn state. Reopen it as ordinary conversation history.

Rust consumers use `agent::agent_build_checkpoint`. Repeated calls return equivalent snapshots; the host owns timing, storage, identities, execution, permissions, and cancellation. Tool IDs should be unique across the retained output because result matching spans the whole snapshot.

Explicit chat stop captures a checkpoint before settling. Background cancellation returns no output.

## Permission gating

Before executing any tool, the loop checks the [permission policy](../tools/permissions.md): a tool can be `always` allowed, `never` allowed (blocked), or require asking. This is checked per-call, so the same tool can have different policies in different contexts (e.g. editing core docs is allowed during onboarding but confirmed in normal chat).
