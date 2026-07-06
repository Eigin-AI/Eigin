# MCP servers

MCP (Model Context Protocol) lets users extend the agent with external tools and data sources. An MCP server exposes tools over a network connection, and Eigin makes them available to the agent alongside its built-in tools.

## Transport

Eigin connects over **Streamable HTTP**: the server exposes an HTTP endpoint, and the client sends JSON-RPC requests and receives responses or streams. It's simple and firewall-friendly, working with cloud-hosted servers and local processes alike.

## Authentication

- **Open servers**: no auth. Connect with a URL and go. Useful for local servers or trusted internal tools.
- **OAuth 2.1 servers**: the full authorization flow. Eigin discovers the server's OAuth metadata, registers itself as a client automatically (no manual OAuth app), and sends the user to the server's authorization page in an in-app browser to log in and grant access. Access and refresh tokens are stored securely via on-device platform APIs and refreshed automatically when they expire.

## Tool discovery

On connection, Eigin calls `tools/list` to discover tools, each with a name, description, and parameter schema. These are cached locally so the agent sees descriptions without reconnecting every turn. Discovery re-runs on explicit refresh or when the connection is re-established.

## Trust boundaries

MCP tools are external: the server is controlled by someone else, and responses could contain anything, including prompt injection. Eigin treats the boundary seriously:

- External tools default to **ask**: the user approves each use (see [Permissions](./permissions.md)).
- Per-tool overrides let the user change the level for individual MCP tools.
- The agent sees MCP tools alongside built-in ones, but the permission system enforces the boundary.

This lets power users grant broad access to trusted servers while keeping untrusted tools behind a prompt.
