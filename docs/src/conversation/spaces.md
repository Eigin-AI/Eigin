# Spaces

Spaces let users organize chats by context and isolate knowledge between different working domains. A single agent often serves multiple roles: work projects, personal tasks, creative writing. Spaces solve two problems at once: they organize the chat list, and they create knowledge boundaries.

## How it works

A space belongs to an agent and has a name, symbol, instructions, and a privacy setting. Private spaces seal their chats and knowledge from the rest of the agent's context. Non-private spaces are organisational only. The instructions are injected into the per-turn hint block whenever the user is chatting within that space, giving the agent persistent context about the current domain without the user needing to repeat it.

### Organization

Spaces group chats by context. A user might have a "Work" space, a "Personal" space, and a "Project X" space. The chat list can be filtered by space.

### Knowledge isolation

Knowledge created within a private space is only accessible within that space. Knowledge created anywhere else is accessible everywhere. For details on how knowledge scoping works, see [Knowledge - Scoping](../agents/knowledge.md#scoping).

### Creating a space

Spaces can be created from within a normal conversation or through a dedicated setup conversation. Either way, the agent interviews the user about the space's purpose, picks a name and symbol, sets instructions, and creates the space via a tool call.
