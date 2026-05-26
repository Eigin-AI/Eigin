# Core

Agents in Eigin have an essence. It shapes every conversation and makes the interaction feel personal and directed.

## Presentation

The agent has a way of appearing to the user. It has a name, a symbol and a voice. These can be set by the user, or by the agent.

### Voices

The agent's voice is selected from the user's preferences. Eigin ships local TTS models for each supported language; where one is available it is used automatically, otherwise the OS voice is the fallback. Users can also choose a specific voice manually.

## Core texts

The agent has three persistent "core" texts that define its character. These are injected into every system prompt.

### Identity

The specifics of who the agent is. Role, capabilities, tone, constraints. This shapes what the agent does and how it communicates.

### User

A profile of the person the agent talks to. Likes, dislikes, working style, relevant context. This builds up over time as the agent learns about the user through conversation.

### Soul

A shared value system: principles and philosophy. The essence or "spirit" of the agent.

This layout is inspired by constitutional AI. The agent can read and edit these texts using tools, so it can update its way of being over time.

## Permissions

The agent can always read its core texts. Updating them requires user consent.
