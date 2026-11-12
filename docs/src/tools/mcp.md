# MCP servers

MCP (Model Context Protocol) connects the agent to external tools and data sources over **Streamable HTTP**. Manage connections in **Settings → Connections → Integrations**.

## Connecting

| Route | Setup |
|---|---|
| [MCP preset](../integrations/mcp-presets.md) | Pick a service; Eigin supplies its endpoint. |
| Custom server | Choose **Connect by address** and enter an HTTP endpoint. |
| Chat | Discover a preset skill, confirm connection, then complete setup. |

Open servers connect directly. OAuth servers open the service's sign-in flow; tokens stay in on-device secure storage and refresh automatically. Some servers require client credentials.

## Tools and permissions

- Connection discovers and caches tools and server instructions; reconnection refreshes them.
- Tools enter the conversation when their skill activates.
- External tools default to **ask**, with per-tool overrides in [Permissions](./permissions.md).
- Server responses are external content and can contain prompt injection.

Cancelled or failed setup leaves the skill inactive and permits a retry after fresh confirmation. **Not now** remembers a decline; setup remains available in Connections.
