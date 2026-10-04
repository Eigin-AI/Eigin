# AI Act self-assessment

| Version | Date | Author | Status |
|---|---|---|---|
| 0.1 | 2026-09-02 | Daniel Rothmann | Draft |

## Introduction

Eigin is a local-first personal AI app, described in the [compliance overview](./README.md).

This document is our self-assessment against [Regulation (EU) 2024/1689](https://eur-lex.europa.eu/eli/reg/2024/1689/oj), the AI Act, as amended by the Digital Omnibus on AI ([Regulation (EU) 2026/1744](https://eur-lex.europa.eu/eli/reg/2026/1744/oj)). It sets out how Eigin is scoped under the Act, which obligations apply, and how each is met. It is not legal advice.

We rely on the Commission's [AI Act FAQ](https://digital-strategy.ec.europa.eu/en/faqs/navigating-ai-act), the [guidelines on the AI system definition](https://digital-strategy.ec.europa.eu/en/library/commission-publishes-guidelines-ai-system-definition-facilitate-first-ai-acts-rules-application), the [Article 50 FAQ](https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act), and the [GPAI guidelines](https://digital-strategy.ec.europa.eu/en/policies/guidelines-gpai-providers).

## System context

See the [compliance overview](./README.md).

## Scope

### Is Eigin an AI system?

Yes. The App takes natural-language input, infers text and tool calls from a machine-learned model, and acts on the user's environment. That meets the Article 3(1) definition.

### What is Eigin's role?

| Role | Applies | Why |
|---|---|---|
| **Provider of an AI system** (Art. 3(3)) | Yes | Eigin ApS places the App on the EU market under its own name |
| **Provider of a GPAI model** (Art. 3(3), 3(63)) | No | Eigin does not train or fine-tune a model today. Gemma 4 E2B is mirrored unmodified, and the Relay forwards to models hosted by others. Per the GPAI guidelines, serving or distributing another's model does not make you its provider |
| **Deployer** (Art. 3(4)) | Internally | Eigin ApS staff use the App in their work, which makes Eigin a deployer of its own system. For a non-high-risk system the deployer duties are AI literacy (Art. 4) and Article 50(4) labelling, both covered below. Users deploying the App for personal use are out of scope (Art. 2(10)) |
| **Open-source exemption** (Art. 2(12)) | Partly | The App is AGPL-3.0, so the Act does not apply to it, *except* that Article 5 and Article 50 still do. Both are assessed below |

### Risk classification

| Tier | Verdict | Why |
|---|---|---|
| **Prohibited** (Art. 5) | No | See [Article 5](#article-5-prohibited-practices) |
| **High-risk** (Art. 6, Annex III) | No | Eigin is a general-purpose personal assistant. It has no intended purpose in any Annex III area: no biometrics, no access decisions for education, employment, credit, or essential services, no law enforcement or migration use, no safety components. The Aula integration reads a parent's school messages; it does not evaluate students or determine access to education |
| **Transparency** (Art. 50) | Yes | The agent interacts directly with a person, and it generates text. Article 50(1) and 50(2) apply |
| **Minimal** | Otherwise | No further obligations |

Article 50 applies from 2 August 2026, and Eigin complies with all of it from that date without relying on the Omnibus grace period for marking.

## Obligations

### Article 5: prohibited practices

| Practice | Verdict | Evidence |
|---|---|---|
| 5(1)(a), (b) Manipulation, exploiting vulnerabilities | Not present | The agent acts on explicit user requests. Proactive behaviour is a user setting with a "reactive" off level ([initiative](../agents/initiative.md)). No subliminal, dark-pattern, or engagement-optimising techniques exist; there is no tracking or ad incentive ([philosophy](../philosophy.md)) |
| 5(1)(c) Social scoring | Not present | No scoring of persons. The knowledge graph is private to the device and serves the user only |
| 5(1)(d) to (h) Predictive policing, facial scraping, emotion recognition, biometric categorisation, remote biometric ID | Not present | No biometric processing. Speech recognition transcribes words on-device and identifies nobody ([voice](../voice/README.md)). No emotion or sentiment inference exists in the codebase |
| 5(1)(i) Non-consensual intimate imagery, CSAM | Not present | The App generates no images, audio clones, or video |

### Article 50(1): interaction disclosure

The user must be informed they are interacting with an AI system, unless obvious.

| Aspect | Verdict | Evidence |
|---|---|---|
| Disclosure at first interaction | Met | The App is marketed and described as a personal AI agent. The first conversation is an onboarding chat whose prompt frames the agent as "a new personal AI agent being set up inside Eigin" ([`chat.jinja`](https://code.eigin.ai/dev/eigin/-/blob/main/design/prompts/onboarding/chat.jinja)) |
| Never claims to be human | Met | Every system prompt opens with "an AI agent in the Eigin app" ([`preamble.jinja`](https://code.eigin.ai/dev/eigin/-/blob/main/design/prompts/system/partials/preamble.jinja)). The onboarding prompt instructs: never pretend to be human or to have a body |
| Voice | Met | Live call uses the native call UI with the agent's name and symbol, initiated by the user in the App ([live call](../voice/live-call.md)). The same prompts apply |
| Third parties | Met | Content the agent produces for others leaves the device only through tools the user approves per call, from the user's own accounts, after reviewing what is sent ([permissions](../tools/permissions.md)). It carries the machine-readable mark below |

### Article 50(2): marking synthetic content

Outputs must be marked in a machine-readable format and detectable as artificially generated, as far as technically feasible.

| Modality | Verdict | Evidence |
|---|---|---|
| Text | Met | An invisible zero-width mark is appended when text leaves the App: full-message copy and agent-sent email ([watermarking](../watermarking.md)). A detector ships in the CLI (`eigin watermark detect`). The mark is not robust to paraphrase or stripping; the Act's feasibility standard weighs cost and the state of the art, and generation-time watermarking is unavailable to an app that does not run the model |
| Text exclusions | N/A | Source code and short strings are excluded by the guidelines. Text leaves the App only through the marked paths above |
| Audio | N/A | Text-to-speech renders to the device speaker in real time. No audio file is produced, stored, or shareable, so there is no artefact to mark. The listener is the user who chose the voice |
| Image, video | N/A | Not generated |

### Article 50(4): deepfakes and public-interest text

These are deployer obligations. They bind Eigin ApS for its internal use, and users only in professional use.

| Aspect | Verdict | Evidence |
|---|---|---|
| Deepfakes | N/A | No image or video generation. TTS voices are generic synthetic voices from PocketTTS and Plapre Pico, or OS voices. None imitates an existing person |
| Public-interest text | Met | Eigin ApS publishes no agent-written text without human editorial review, which the guidelines exempt. A user publishing such text professionally carries the duty themselves; the watermark helps them and others detect it |

### Article 4: AI literacy

Providers must ensure sufficient AI literacy of their staff.

| Aspect | Verdict | Evidence |
|---|---|---|
| Staff literacy | Met | Eigin's team builds the agent harness and works with model behaviour, prompt injection, and permission design daily ([privacy and security](../privacy.md)). This document and the CASA assessment are part of that practice |

### Value chain: GPAI models

Eigin integrates models it does not train. The GPAI provider obligations (Art. 53) fall on the model providers.

| Model | Provider | How Eigin uses it |
|---|---|---|
| Gemma 4 E2B | Google | Unmodified weights, mirrored and checksum-verified ([local model](../ios/local-model.md)) |
| Hosted models via the Relay | Mistral, TensorX, Corti | Forwarded unread ([relay](../relay.md)) |
| User's own provider | Chosen by the user | Any OpenAI-compatible API, under the user's key and terms |

Eigin relies on the providers' published model documentation to understand capabilities and limits. Model routing and the catalog record per-model capabilities ([providers](../providers.md)). Because Eigin does no fine-tuning, the downstream-modification threshold in the GPAI guidelines is not approached.
