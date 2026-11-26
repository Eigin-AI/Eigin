# The agentic loop

A turn starts with a user request and ends with a reply, a stop, or a failure. It can include several model responses and tool executions. Each tool result becomes context for the model's next response.

The SDK coordinates progress and keeps the turn's output. The host connects it to inference, tools, the user interface, and storage.

## How the pieces work together

| Piece | Responsibility |
|---|---|
| **Host** | Prepares the request, streams from the [provider](../providers.md), checks [permissions](../tools/permissions.md), and executes tools. |
| **Round** | Collects one streamed response and its tool exchanges. Distinguishes a final reply, a tool batch, and incomplete output. |
| **Turn** | Decides whether to request another response, recover, or finish. Applies the turn's limits. |
| **Output** | Keeps messages in order, tracks the current draft, and determines what can be retained. |

The host submits initial context to one SDK `ChatTurn` operation. The SDK coordinates provider requests, feeds responses into rounds, and follows the turn's decisions. It asks the host to execute permitted tools, records accepted results, and includes them in the next request. The host observes progress and can stop the operation.

One output owner stays with the turn throughout. It collects completed exchanges and prose while the host renders the live draft. Draft identity follows the prose into its committed message, so the streaming row becomes the saved row without changing identity.

See [turn progression](../sdk/turn-progression.md) for the SDK integration workflow.

## Silent and interrupted turns

An empty final reply or recoverable cloud-stream interruption gets one automatic continuation per turn. Completed work and retained partial prose stay in context; a request-only system hint asks the model to finish. Cancellation, limits, refusals, and explicit background completion do not trigger recovery.

Repeated silence shows a tappable continuation card. The credits-ready card offers the same action: resume saved work without resending the user's message.

## Safe checkpoints

A checkpoint is the output that can be saved when a turn stops or fails. Reading one leaves the live turn unchanged.

- **Completed work stays:** assistant messages, tool results, and completed local inline exchanges retain their order.
- **Partial prose survives:** the current draft can be saved using its streaming identity.
- **Unfinished actions remain explicit:** outstanding cloud tool calls receive “completion unknown” results. A later continuation can check what happened before repeating an action.

For example, if two tools are requested and the user stops after the first result, the checkpoint includes the requested batch, the first result, and an uncertainty result for the second call.

The complete `Experimental.Agent.ChatTurn` operation owns output and round progress. It returns output with provenance; the host maps that provenance to app message IDs, chooses when to checkpoint, and saves the snapshot. After saving, the host settles its live presentation state. The saved messages become ordinary conversation history for a later turn.

Explicit chat stop closes admission and captures a checkpoint before settling. Background cancellation currently returns no output. The SDK rejects late tool results after stop or cancellation, including results from an earlier operation after a replacement turn starts. Already-executed side effects are not undone.

Lower-level output and stateless checkpoint APIs remain available for consumers that compose their own orchestration. iOS uses the complete-turn operation.
