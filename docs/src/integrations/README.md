# Integrations

Integrations connect external services so the agent can use them directly. A **capability** (e.g. `email`) is a named area of behavior an integration provides; skills declare the capabilities they need. A capability's tools are only in context when an integration providing it is connected *and* a skill needing it is active.

[MCP connections](../tools/mcp.md) discover tools from the server. Their skills control when those tools enter the conversation. Bundled presets also appear in the integration picker and skill search before connection; Eigin supplies the endpoint during setup.

Manage integrations in **Settings → Connections → Integrations**. [Platform integrations](./platform.md) (Apple Health, Calendar, Reminders, Location) connect through an iOS permission instead of an account. Connecting one runs its authorization flow and records which capabilities were actually granted, since a user can approve some and deny others — only granted capabilities' tools appear. Only one connected integration can provide a given capability at a time.

When a connection expires (a revoked OAuth refresh token, an expired Aula session, a rotated mail password), the agent's tool errors say the user can fix it themselves, and the Connections list flags the integration with a warning icon. The fix is **Reconnect** on the integration's detail screen: it re-runs the same connect flow under the *existing* integration id, refreshing credentials and granted capabilities in place. Capability-provider selections and tool permissions keep pointing at the same integration, unlike a remove and re-add, which mints a new one.

Integration tools appear in the normal [permissions](../tools/permissions.md) screen once connected, defaulting to **ask** like any external tool.

## Available integrations

| Integration | Capability | Auth |
|---|---|---|
| [Google](./google.md) | `email` | OAuth |
| [Microsoft](./microsoft.md) | `email` | OAuth |
| [IMAP](./imap.md) | `email` | Manual server credentials |
| [Aula](./aula.md) | `aula` | Web-session login (UniLogin/MitID in a WKWebView) |
| [Apple Health](./platform.md) | `health` | iOS permission (platform) |
| [Apple Calendar](./platform.md) | `calendar` | iOS permission (platform) |
| [Apple Reminders](./platform.md) | `reminders` | iOS permission (platform) |
| [Location](./platform.md) | `location` | iOS permission (platform) |

## Available MCP presets

See [MCP presets](./mcp-presets.md) for bundled services, authentication, and requirements.

## Connecting from a chat

A skill with a missing capability can still be found. On first activation, the agent is prompted to confirm with the user. After confirmation, a matching retry can open the connect sheet.

Successful connection activates the skill. Declining, cancelling, or failing setup leaves it inactive. An explicit decline is remembered per capability or MCP preset. Cancellation and failure allow a later attempt after fresh confirmation; failures report what went wrong. Already-connected skills activate immediately. See [platform integrations](./platform.md#connecting-from-a-chat) and [MCP setup](../tools/mcp.md#connecting).
