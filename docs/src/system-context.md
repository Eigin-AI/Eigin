# System context

This page describes Eigin at the system level. For implementation details on a specific platform, see [iOS Implementation](./ios/README.md).

## The pieces

```mermaid
flowchart LR
    User["<b>User</b>"]

    subgraph Device["User device"]
        Chat["<b>Chat</b><br/>messages, input,<br/>interaction modes"]
        Agent["<b>Agent</b><br/>identity, knowledge,<br/>chats, skills, intents"]
        Gatekeeper["<b>Gatekeeper</b><br/>per-turn context<br/>+ pre/post-processing"]
        Storage["<b>Storage</b><br/>chats, knowledge,<br/>intents, settings"]
        Voice["<b>Voice</b><br/>dictation, TTS,<br/>live call"]
        OS["<b>OS APIs</b><br/>calendar, reminders,<br/>location, microphone"]
        ToolsMCP["<b>Tools & MCP</b><br/>built-in tools<br/>+ MCP clients"]
        LocalModel["<b>Local model</b><br/>on-device,<br/>hardware accelerated"]
    end

    CloudModel["<b>Cloud models</b><br/>OpenAI, Anthropic,<br/>Google, Mistral, etc."]
    Relay["<b>Eigin Relay</b><br/>(optional)"]
    MCPServers["<b>MCP servers</b><br/>third-party"]

    User --- Chat
    Chat --- Voice
    Chat --- Agent
    Chat --- Storage
    Voice -.- OS -.- ToolsMCP
    Storage --- Agent
    Agent --- ToolsMCP
    Agent --- Gatekeeper
    Gatekeeper --- LocalModel
    Gatekeeper --- CloudModel
    ToolsMCP --- Relay
    ToolsMCP --- MCPServers

    classDef eigin min-width:160px
    class Chat,Agent,Gatekeeper,Storage,Voice,ToolsMCP,LocalModel eigin
```

### Chat

Where the user meets the agent. A chat is a persistent sequence of messages; the user can type directly or dictate through the voice subsystem. Chats live in storage and can be grouped into [spaces](./conversation/spaces.md). See [Conversation](./conversation/README.md).

### The agent

A persistent AI personality with its own identity, knowledge, conversation history, and goals. A device runs one agent at a time. See [The Agent](./agents/README.md).

### Gatekeeper

Sits between the agent and the inference provider. Hydrates each turn with dynamic context (skills, intents, interaction mode, space, hints) and is the seam for future input/output safety work. See [The gatekeeper](./conversation/context.md).

### Storage

Chats, knowledge, intents, settings, and provider configuration live on the device.

### Voice

The voice subsystem handles on-device speech recognition, text-to-speech, and a half-duplex live call mode for hands-free conversation. See [Voice](./voice/README.md).

### Tools and MCP

Tools are how the agent acts - built-in tools that integrate with the OS and internet, and MCP clients that connect to external servers. Both flow through the same permission model. See [Tools](./tools/README.md) and [MCP servers](./tools/mcp.md).

### Inference providers

The agent calls one of two kinds of provider:

- **Cloud**: any OpenAI-compatible API. The user supplies the key.
- **Local**: a hardware-accelerated on-device model. No key, no network.

See [Inference providers](./providers.md).

### Eigin Relay

An optional connectivity service operated by Eigin, used for features that need third-party API keys the app can't ship. See [Eigin Relay](./relay.md).
