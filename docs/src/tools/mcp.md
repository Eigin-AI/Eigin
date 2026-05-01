# MCP servers

MCP (Model Context Protocol) lets users extend the agent with external tools and data sources. An MCP server exposes tools over a network connection, and Eigin makes those tools available to the agent alongside its built-in tools.

## Why MCP

Eigin ships with a focused set of built-in tools. MCP makes the system open-ended: any external service that implements the protocol can provide tools to the agent. A project management server exposes task queries. A code search server exposes repository lookups. The agent sees a flat list of tools — it doesn't know or care which ones are built-in and which come from MCP.

This keeps Eigin's core small while making the agent arbitrarily extensible.

## Transport

Eigin connects to MCP servers over **Streamable HTTP**. The server exposes an HTTP endpoint; the client sends JSON-RPC requests and receives responses (or streams) over HTTP. This is a simple, firewall-friendly transport that works with cloud-hosted servers and local processes alike.

## Authentication

MCP servers fall into two categories:

**Open servers** require no authentication. Connect with a URL and go. Useful for local servers or trusted internal tools.

**OAuth 2.1 servers** use the full OAuth authorization flow:

1. **Discovery** — Eigin fetches the server's OAuth metadata (authorization endpoint, token endpoint, supported grant types)
2. **Dynamic client registration** — Eigin registers itself as an OAuth client with the server, receiving a client ID. This happens automatically — the user doesn't need to manually create an OAuth app
3. **Authorization** — The user is presented with the server's authorization page (in-app browser). They log in and grant access
4. **Token management** — Eigin stores the access token and refresh token securely. Tokens are refreshed automatically when they expire

The OAuth flow runs entirely on-device. Tokens are stored in the Keychain alongside API keys.

## Tool discovery

When a server connection is established, Eigin calls `tools/list` to discover available tools. Each tool comes with a name, description, and JSON schema for its parameters. These are cached locally so the agent can see tool descriptions without reconnecting on every turn.

Tool discovery runs again when the user explicitly refreshes, or when the server connection is re-established.

## Trust boundaries

MCP tools are external — the server is controlled by someone else, and tool responses could contain anything, including attempts at prompt injection. Eigin treats this boundary seriously:

- **External tools default to "ask"** — the user must approve each use, as described in [Permissions](./permissions.md)
- **Per-tool permission overrides** — the user can change the permission level for individual MCP tools in the agent's permission settings
- **The agent sees MCP tools alongside built-in tools** — but the permission system enforces the trust boundary transparently

This model lets power users grant broad access to trusted servers while keeping untrusted tools behind a confirmation prompt.

## Configuration

MCP servers are configured globally in Settings. Each server has a name, URL, and authentication method. Once connected, the server's tools become available for per-agent permission configuration — you can enable a server's tools for your work agent but not your personal agent.
