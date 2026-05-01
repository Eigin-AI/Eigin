# Spaces

Spaces let users organize chats by context and isolate knowledge between different working domains.

## Why spaces

A single agent often serves multiple roles — work projects, personal tasks, creative writing. Without spaces, knowledge from one context can bleed into another. Spaces solve two problems at once: they organize the chat list, and they create knowledge boundaries.

## How it works

A space belongs to an agent and has a name, emoji, and instructions. The instructions are injected into the system prompt whenever the user is chatting within that space, giving the agent persistent context about the current domain without the user needing to repeat it.

### Organization

Spaces group chats by context. A user might have a "Work" space, a "Personal" space, and a "Project X" space. The chat list can be filtered by space.

### Knowledge isolation

Knowledge saved within a space is only accessible within that space. Global knowledge (saved outside any space) is accessible everywhere. For details on how knowledge scoping works, see [Knowledge — Scoping](../agents/knowledge.md#scoping).

### Bootstrap

New spaces are created through a conversation, following the same pattern as [agent bootstrap](../agents/README.md#bootstrap). The agent interviews the user about the space's purpose, picks a name and emoji, sets instructions, and creates the space via a tool call.
