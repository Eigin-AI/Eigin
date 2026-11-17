# MCP presets

Bundled connection details for services available through the integration picker and skill discovery in chat.

| Preset | Endpoint | Authentication | Requirement |
|---|---|---|---|
| [Dinero](https://mcp.dinero.dk) | `https://mcp.dinero.dk` | Visma Connect OAuth | Dinero Pro or Total subscription tier |
| [Basecamp](https://basecamp.com/ai) | `https://mcp.basecamp.com/mcp` | Basecamp OAuth | Basecamp account; choose an account and read-only or full access during sign-in |
| [Notion](https://developers.notion.com/guides/mcp/get-started-with-mcp) | `https://mcp.notion.com/mcp` | Notion OAuth with PKCE and the app callback | Notion workspace membership on any plan; guests cannot connect. Workspace policies may require admin approval. |
| [Pleo](https://developers.pleo.io/docs/current/pleo-mcp/how-tos/installation/custom-mcp) | `https://mcp.pleo.io/mcp` | Browser-based OAuth 2.0 | Eligible Pleo plan; an admin must enable MCP access under Settings → General → Pleo AI for each entity and allow the connecting user access. |

Setup and permissions follow the shared [MCP connection flow](../tools/mcp.md). Connections added by address stay independent of presets.
