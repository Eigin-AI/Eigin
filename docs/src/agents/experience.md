# Experience

The agent experiences the world through conversation. A chat is the agent's most detailed kind of context. The agent can read not only the chat it's currently in, but also the record of past chats.

## Chats

A chat is a persistent conversation between the user and the agent. Each chat has:

- A sequence of messages (user, agent, tool calls, tool results)
- A title, auto-generated from the first exchange and editable
- Created and updated timestamps
- An optional [space](../conversation/spaces.md) it belongs to

Chats live on the device. The only time messages go off-device is as part of a request to the inference provider for the active turn - and only while still within the live context window. See [compaction](../conversation/compaction.md).

### Scoping

Chats are scoped per space:

- **Global chats** (no space): visible from anywhere
- **Space-scoped chats**: only visible within their space

When the user is in a space, the chat list shows that space's chats. Outside any space, all chats are shown.

## Accessing past chats

The current chat is always in working context. To reach beyond it, the agent has tools for browsing its own history:

- **List chats** - scan recent chats
- **Get chat transcript** - read a specific chat as a clean transcript

These tools respect space boundaries: an agent can't read chats from other private spaces.

## Permissions

Both tools are read-only and default to **always**: the agent browses its own history without prompting the user. The agent never modifies past chats; it can only read them.
