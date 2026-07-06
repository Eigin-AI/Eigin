# Experience

The agent experiences the world through conversation. A chat is its most detailed kind of context, and it can read both the current chat and the record of past ones.

## Chats

A persistent conversation between the user and the agent. Each chat has:

- A sequence of messages (user, agent, tool calls, tool results)
- An auto-generated, editable title
- Created and updated timestamps
- An optional [space](../conversation/spaces.md)

Chats live on the device. Messages go off-device only as part of the inference request for the active turn, and only while still in the live context window. See [compaction](../conversation/compaction.md).

## Scoping

- **Global chats** (no space): visible from anywhere.
- **Space-scoped chats**: visible within their space.

## Accessing past chats

The current chat is always in working context. To reach beyond it, the agent has read-only tools: **list chats** to scan recent ones, **get chat transcript** to read a specific chat. Both respect space boundaries, so the agent can't read chats from other private spaces.

## Permissions

The agent can always read its own history. It can never modify past chats.
