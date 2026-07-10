# Integrations

Integrations connect external services so the agent can use them directly. A **capability** (e.g. `email`) is a named area of behavior an integration provides; skills declare the capabilities they need. A capability's tools are only in context when an integration providing it is connected *and* a skill needing it is active.

This differs from [MCP](../tools/mcp.md): MCP tools are opaque and injected into every turn once connected. Integration capabilities are known in advance, so they route through the same skill-activation mechanism as built-in tools instead of flooding context.

Manage integrations in **Settings → Connections → Integrations**. Connecting one runs its authorization flow and records which capabilities were actually granted, since a user can approve some and deny others — only granted capabilities' tools appear. Only one connected integration can provide a given capability at a time.

Integration tools appear in the normal [permissions](../tools/permissions.md) screen once connected, defaulting to **ask** like any external tool.

## Available integrations

| Integration | Capability | Auth |
|---|---|---|
| [Google](./google.md) | `email` | OAuth |
| [Microsoft](./microsoft.md) | `email` | OAuth |
| [IMAP](./imap.md) | `email` | Manual server credentials |
