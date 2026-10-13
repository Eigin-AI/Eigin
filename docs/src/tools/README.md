# Tools

Tools give the agent the ability to act: adding to its knowledge base, editing its core documents, managing spaces, and more. Each tool is defined by a protocol, collected in a central registry, and gated by a [permission system](./permissions.md).

## How it works

Every tool declares its name, permission requirements, a JSON schema (sent to the LLM so it knows how to call the tool), and an execute function. The registry provides definitions to the LLM and dispatches calls by name. Factory methods build different tool sets per context: the full set for normal chat, a restricted set for setup conversations, and a filtered set for background sessions.

## Built-in tools

Built-in tools cover the agent's core capabilities: knowledge management, web search and fetch, space management, self-modification, and awareness of time and location. Integration tools divide into account integrations, like email, and platform integrations — the phone permissions for Apple Health, Calendar, Reminders and Location. Some are context-specific and appear only in certain session types. All tools return a JSON envelope with optional `result`, `errors`, and `warnings`.

## Adding a tool

1. Create a file implementing the tool protocol: name, capabilities, JSON schema, execute function.
2. Add its capability to the capability enum.
3. Register it in the tool registry.

The protocol and helpers handle argument parsing and output formatting, so most of the work is the tool's logic.
