# Core

An agent's essence shapes every conversation and makes the interaction feel personal and directed.

## Presentation

The agent has a name, a symbol, and a voice, set by the user or by the agent itself.

The voice comes from the user's preferences. Eigin ships local TTS models per supported language; where one exists it's used automatically, otherwise the OS voice is the fallback. Users can also pick a specific voice.

## Core texts

Three persistent texts define the agent's character, injected into every system prompt. The layout is inspired by constitutional AI. The agent can read and edit them with tools, updating its way of being over time.

| Text | About | What it holds |
|---|---|---|
| **Identity** | The agent itself | Role, capabilities, tone, constraints |
| **User** | The person it talks to | Likes, dislikes, working style, context |
| **Soul** | Shared values | Principles and the spirit of the agent |

## Permissions

The agent can always read its core texts. Updating them requires user consent.
