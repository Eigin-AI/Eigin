# Core
Agents in Eigin have an essence. They are part of every conversation and help shape the interaction in a way that feels personal and directed.

## Presentation
The agent has a way of appearing to the user. It has a name, a symbol and a voice. These can be set by the user, or by the agent.

### Voices
The agent's voice is selected from the user's preferences. Eigin ships local TTS models for each supported language; where one is available it is used automatically, otherwise the OS voice is the fallback. Users can also choose a specific voice manually.

## Core texts
The agent has three persistent "core" texts that define its character. These are injected into every system prompt.

### Identity
The specifics of who the agent is. Role, capabilities, tone, constraints. This impacts what the agent does and how it communicates.

### User
A profile of the person the agent talks to. Likes, dislikes, working style, relevant context. This builds up over time as the agent learns about the user through conversation.

### Soul
A shared value system: principles and philosophy. This is the essence or "spirit" of the agent. The Soul text makes the agent feel lively.

This layout was inspired by Anthropic's constitutional AI. The agent can read and edit these texts using tools, so it can update its way of being over time.

## Bootstrap
The agent bootstrap is a setup flow where a new agent interviews the user to establish itself.

Instead of filling out forms, the user has a conversation. The agent asks questions, figures out who it should be, who the user is, and how it can help, then writes the answers to its own core texts.

During bootstrap, the agent has a restricted tool set (core text tools, presentation settings, and a "done" trigger). Setup completes when the agent signals it's ready or after enough conversation has happened.

## Permissions
During bootstrap, the agent is allowed to read and write its presentation and core texts freely. In normal conversations it can always read, but requires user consent to update.
