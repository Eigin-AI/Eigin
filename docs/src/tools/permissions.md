# Permissions

Tools declare capabilities, and a permission policy resolves the level for each tool call:

- **Always** — execute without prompting
- **Ask** — prompt the user for approval
- **Never** — block entirely; the tool is hidden from the agent, it doesn't know it exists

## Grants hierarchy

Permissions operate at three levels:

1. **Default grants** — each tool ships with a sensible default based on its risk profile (see boundaries below)
2. **Agent grants** — the user can override defaults per-agent in the permissions menu. These persist across all chats
3. **Chat grants** — during a chat, the user can "allow for this chat" instead of just "allow once," avoiding repeated prompts for tools used frequently in one conversation

## Permission boundaries

Three boundaries determine the default permission level:

1. **Read vs write** — Read-only tools (reading core documents, searching knowledge, getting time/location) default to **always**. Anything that modifies state (editing core docs, deleting knowledge, creating spaces) defaults to **ask**
2. **Internal vs external** — External tools (web search, web fetch, [MCP servers](./mcp.md)) default to **ask** even for reads, because external data carries prompt injection risk
3. **User availability** — The permission system is aware of whether the user can be prompted. In text chat, prompts are shown inline. In a [live call](../voice/live-call.md), the phone may be in the user's pocket. When prompting is unavailable and a tool requires permission, it is denied by default. The agent is informed and can tell the user to open the app if it needs approval

During bootstrap, editing core documents is auto-allowed. During live voice calls, `ask`-level tools are blocked because the UI can't show permission prompts on the lock screen.
