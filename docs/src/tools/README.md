# Tools

The tool system gives the agent the ability to take actions like adding to its knowledge base, editing its own core documents, managing spaces, and more.

Tools are defined by a protocol, collected in a central registry, and gated by a [permission system](./permissions.md).

## How it works

Every tool implements a protocol that declares its name, permission requirements, a JSON schema (sent to the LLM so it knows how to call the tool), and an execute function.

Tools are collected in a registry that provides definitions to the LLM and dispatches calls by name.

Factory methods create different tool sets for different contexts: the full set for normal chat, a restricted set for agent bootstrap and space bootstrap, and a filtered set for background sessions.

## Built-in tools

Built-in tools cover the agent's core capabilities:

- **Self-modification** — reading and editing core documents, changing presentation
- **Knowledge** — search, get, add, update, delete (see [Knowledge](../agents/knowledge.md))
- **Space management** — creating and managing spaces
- **Web access** — search and fetch
- **Utilities** — time/location, email composition

Some tools are context-specific: `done` only appears during bootstrap, `background_notify` only during background sessions.

All tools return JSON with an optional `result`, `errors`, and `warnings` envelope.

## How to add a new tool

1. Create a new file implementing the tool protocol — name, capabilities, JSON schema, execute function
2. Add the tool's capability to the capability enum
3. Register it in the tool registry

The protocol and helpers handle argument parsing and output formatting, so most of the work is just the tool's logic.
