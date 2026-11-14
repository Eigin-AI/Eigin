# Context paging

Eigin pages conversation history early to limit context rot: long histories can dilute the model's attention before the context window is full. Keeping a smaller working conversation also reduces input cost.

## How it works

- Keep recent conversation and active work in context.
- When the conversation grows, omit older tool outputs first, then older turns as needed.
- Preserve the full stored transcript. Paging changes only what is sent to the model.

Chat, live calls, and watch share this behavior. Paging runs locally without requesting a summary. Existing summaries remain readable.

## Recover earlier text

Once a conversation has been paged, each subsequent user turn reminds the agent that earlier history is available. It can search and read user/assistant text through the transcript tools. Tool outputs must be recovered from their original source.

## SDK

The SDK owns sizing and selection. The app applies the selection, remembers it across sessions, and provides transcript access.
