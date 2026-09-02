# Compliance

Eigin shares its compliance self-assessments openly, with claims referenced to the codebase.

| Assessment | Framework | Status |
|---|---|---|
| [CASA](./casa.md) | Cloud Application Security Assessment v2.1.1 | Final, pending lab verification |
| [AI Act](./ai-act.md) | Regulation (EU) 2024/1689 | Draft |
| [GDPR](./gdpr.md) | Regulation (EU) 2016/679 | Draft |

## Legal entity

Eigin ApS (CVR 46428765, Denmark) publishes the Eigin App and operates the Eigin Relay. Source is at [code.eigin.ai](https://code.eigin.ai/dev/eigin) under AGPL-3.0.

## System context

Eigin is a local-first personal AI app. The agent, its memory, and its tool calls execute on the user's device. The App can run an AI model on-device, or send conversations to a hosted inference service.

| Component | What it is |
|---|---|
| **Eigin App** | Native client. Runs the agent and its tools against a local or hosted model, and holds credentials for connected accounts |
| **Eigin Relay** | Connectivity service. Proxies inference and search, manages inference credits, and serves on-device model files. Backed by a database for credits and quotas, and an object store mirroring model files |

The system depends on these external services:

| Dependency | Relationship |
|---|---|
| **AI models** | Third-party general-purpose models. Small models run on-device; larger models are hosted |
| **Hosted inference providers** | EU-based providers serving models behind the Relay, or a provider the user brings their own key to |
| **Connected account providers** | Third-party accounts the user connects in the App |
| **Web search provider** | Search API, proxied through the Relay |
| **App store** | Sells credit packs and notifies of refunds |

For the full architecture, see [System context](../system-context.md).
