# Spaces

Spaces let users organize chats by context and isolate knowledge between working domains. A single agent often serves multiple roles: work projects, personal tasks, creative writing. Spaces solve two problems at once: they organize the chat list, and they create knowledge boundaries.

## How it works

A space belongs to an agent and has a name, symbol, instructions, and a privacy setting. Private spaces seal their chats and knowledge from the rest of the agent's context; non-private spaces are organisational only. The instructions are injected into the per-turn hint block whenever the user is chatting in that space, giving the agent persistent context about the domain without the user repeating it.

### Organization

Spaces group chats by context: a "Work" space, a "Personal" space, a "Project X" space. The chat list can be filtered by space.

### Knowledge isolation

Knowledge created in a private space is only accessible there. Knowledge created anywhere else is accessible everywhere. See [Knowledge: Scoping](../agents/knowledge.md#scoping).

### Creating a space

Spaces can be created from a normal conversation or a dedicated setup conversation. Either way, the agent interviews the user about the space's purpose, picks a name and symbol, sets instructions, and creates it via a tool call.
