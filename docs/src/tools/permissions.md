# Permissions

Tools declare capabilities, and a permission policy resolves a level for each call:

- **Always**: execute without prompting.
- **Ask**: prompt the user for approval.
- **Never**: block entirely; the tool is hidden from the agent, which doesn't know it exists.

## Grants hierarchy

Permissions operate at three levels:

1. **Default grants**: each tool ships with a default based on its risk profile (see boundaries below).
2. **Agent grants**: the user overrides defaults per-agent in the permissions menu; these persist across chats.
3. **Chat grants**: during a chat, "allow for this chat" avoids repeated prompts for a tool used frequently in one conversation.

## Permission boundaries

Three boundaries set the default level:

1. **Read vs write**: read-only tools (reading core docs, searching knowledge, getting time/location) default to **always**. Anything that modifies state (editing core docs, deleting knowledge, creating spaces) defaults to **ask**.
2. **Internal vs external**: external tools (web search, web fetch, [MCP servers](./mcp.md)) default to **ask** even for reads, because external data carries prompt-injection risk.
3. **User availability**: the system knows whether the user can be prompted. In text chat, prompts show inline. In a [live call](../voice/live-call.md), the phone may be in a pocket, so when prompting is unavailable and a tool needs permission, it's denied by default; the agent is told and can ask the user to open the app.

Setup conversations may use a restricted or customised tool set. During live calls, `ask`-level tools are blocked because the UI can't show prompts on the lock screen.
