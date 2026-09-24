# GDPR self-assessment

| Version | Date | Author | Status |
|---|---|---|---|
| 0.1 | 2026-09-02 | Daniel Rothmann | Draft |

## Introduction

Eigin is a local-first personal AI app, described in the [compliance overview](./README.md).

This document is our self-assessment against [Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj), the GDPR. It sets out which role Eigin ApS holds for each data flow, what personal data the Relay processes, and how each obligation is met. It is not legal advice. The public [privacy policy](https://www.eigin.ai/privacy/) is the user-facing statement; this document is the evidence behind it.

## System context

See the [compliance overview](./README.md).

## Scope

### Roles

Eigin's role differs per data flow, because most processing does not reach Eigin ApS.

| Data flow | Eigin ApS role | Why |
|---|---|---|
| **On-device data**: chats, knowledge, intents, settings, voice | None | Stored and processed on the user's device only ([privacy](../privacy.md)). Eigin ApS has no access. A person using the App for personal purposes is outside the GDPR (Art. 2(2)(c)) |
| **Connected accounts**: Google, Microsoft, IMAP, Aula | None | Read and written on-device with the user's own credentials, held in the Keychain. Content reaches Eigin ApS only if the user sends it for inference through the Relay, covered below |
| **User's own inference provider** | None | The App calls the provider directly with the user's key, under the provider's terms |
| **Eigin Relay**: inference, search, credits, model downloads | Controller (Art. 4(7)) | Eigin ApS decides the purposes and means of the service, and contracts the providers behind it |
| **Self-hosted Relay** | None | The operator is the controller of their instance |

The rest of this document therefore assesses the Relay.

### Special categories

Prompts can contain anything a person tells their agent, including health, beliefs, or relationships. The Relay does not read, analyse, or store them (see below), and the user chooses what to send and when. We rely on the user's explicit choice to route a conversation through the Relay (Art. 9(2)(a)) and hold this point for legal review.

## Personal data processed by the Relay

| Data | Purpose | Basis | Retention | Evidence |
|---|---|---|---|---|
| Prompt and response content | Forward inference to a hosted provider | Contract (6(1)(b)) | None. Held in memory only while streaming, not logged | [`handler.rs`](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/src/inference/handler.rs), [CASA Annex A](./casa.md#annex-a-user-data) |
| Search query | Forward to the search provider | Contract (6(1)(b)) | None. Not logged | [`search/handler.rs`](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/src/search/handler.rs) |
| Client IP address | Rate limiting and abuse prevention; platform access logs | Legitimate interest (6(1)(f)) | Minutes in process memory for the rate limiter. Scaleway edge and object-storage logs, platform default retention | [`rate_limit.rs`](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/src/rate_limit.rs), [`client_ip.rs`](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/src/client_ip.rs) |
| Credit wallet: hash of the purchase or grant, token digest and ciphertext, balance, product | Deliver purchased or granted credits and settle usage | Contract (6(1)(b)); legal obligation (6(1)(c)) for bookkeeping | Credits do not expire, so the wallet persists. Bookkeeping records follow Danish law, then delete | [`0001_create_wallets.sql`](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/migrations/0001_create_wallets.sql) |
| Service logs: wallet ID and error text on failures | Operate and reconcile the service | Legitimate interest (6(1)(f)) | Scaleway Cockpit, platform default retention | [infra alerts](../runbooks/infra-alerts.md) |

Content and queries foreseeably contain personal data, so they are treated as such throughout.

The Relay stores no names, emails, accounts, or device identifiers. A wallet is keyed by a hash of its App Store transaction or grant ID ([`redeem.rs`](https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/src/credits/redeem.rs)).

## Principles (Art. 5)

| Principle | Verdict | Evidence |
|---|---|---|
| Lawfulness, fairness, transparency | Met | Bases above. Privacy policy names the controller, the providers, and the rights |
| Purpose limitation | Met | Each flow serves the request that triggered it. No secondary use, analytics, profiling, or training ([relay](../relay.md)) |
| Data minimisation | Met | The Relay parses only `model` and `stream` from a prompt and reads only token usage from a response. No identity is collected at all |
| Accuracy | N/A | The Relay holds no facts about a person to keep accurate |
| Storage limitation | Met | Content is not stored. The wallet persists because credits do not expire, which is what the user bought |
| Integrity and confidentiality | Met | TLS, encryption at rest, secret handling, scanning, and access control are assessed in [CASA](./casa.md) |
| Accountability | Met | This document, the CASA assessment, and Terraform-declared infrastructure |

## Obligations

| Requirement | Verdict | Evidence |
|---|---|---|
| Information to data subjects (Art. 13) | Met | [Privacy policy](https://www.eigin.ai/privacy/) covers controller, purposes, bases, recipients, retention, rights, and the supervisory authority |
| Data subject rights (Art. 15 to 22) | Met | The Relay cannot identify a person, so Art. 11 applies: rights are exercised by presenting the credit token, which addresses the only record that exists. A wallet can be revoked and deleted on request. No automated decision-making |
| Data protection by design and default (Art. 25) | Met | Local-first architecture, no accounts, purchase-hash wallets, unread forwarding, zero retention ([philosophy](../philosophy.md), [CASA Annex A](./casa.md#annex-a-user-data)) |
| Processors (Art. 28) | Met | See [Annex B](#annex-b-processors). Each processor is bound by a DPA |
| Records of processing (Art. 30) | Met | [Annex A](#annex-a-records-of-processing) is the record |
| Security (Art. 32) | Met | [CASA](./casa.md) sections 4 to 6 |
| Breach notification (Art. 33, 34) | Met | [Data breach runbook](../runbooks/data-breach.md). Detection via [infra alerts](../runbooks/infra-alerts.md) and [security disclosure](https://code.eigin.ai/dev/eigin/-/blob/main/SECURITY.md) |
| Impact assessment (Art. 35) | Not required | Screening: no systematic monitoring, no profiling, no large-scale special-category processing, no new technology applied to persons. Prompts are transient and unread. Revisit if the Relay starts to retain or analyse content |
| Data protection officer (Art. 37) | Not required | No public authority, no large-scale monitoring or special-category processing as a core activity |
| EU representative (Art. 27) | N/A | Established in Denmark |
| International transfers (Art. 44 to 49) | Met | Hosting and inference providers are in the EU. The search provider is in the EU. Some queries may fall through to its fallback source — not covered by the provider's privacy policy or DPA; their FAQ states no retention there. Agent-supplied queries may carry personal data the user didn't intend, so this path is treated as needing vendor confirmation. Apple acts as an independent controller for purchases |
| Children (Art. 8) | N/A | The App is for adults. The basis is contract, not consent |

## Annex A: Records of processing

Record kept under Art. 30(1). Controller: Eigin ApS, CVR 46428765, Denmark, hello@eigin.ai. No DPO.

| Activity | Categories of data subjects | Categories of data | Recipients | Transfers | Erasure | Security |
|---|---|---|---|---|---|---|
| Inference proxy | Relay users | Conversation content, IP address | Hosted inference providers (EU) | None | Immediate; not stored | [CASA](./casa.md) |
| Web search proxy | Relay users | Search query, IP address | Search provider (EU) | None | Immediate; not stored | [CASA](./casa.md) |
| Credit wallets | Purchasers and grant recipients | Purchase or grant hash, token digest, balance | Hosting provider (EU) | None | Wallet on request; bookkeeping per Danish law | [CASA](./casa.md) |
| Model asset mirror | App users downloading a local model | IP address | Hosting provider (EU) | None | Platform log retention | [CASA](./casa.md) |
| Service operations | Relay users | Wallet ID, error text, IP address in platform logs | Hosting provider (EU) | None | Platform log retention | [CASA](./casa.md) |
| Contributor agreements | Contributors to the source code | GitLab user ID and username, agreement version, date, sign comment. For entities, the signed agreement and covered accounts | None | None | Kept while the contribution is distributed, as proof of the license (Art. 17(3)(e)) | Private GitLab project, maintainers only |

## Annex B: Processors

| Processor | Role | Location | Terms |
|---|---|---|---|
| Scaleway | Hosting: containers, database, object storage, logs | EU | [DPA](https://www.scaleway.com/en/contracts/) |
| TensorX | Hosted inference | Ireland, Finland | [DPA](https://tensorx.ai/dpa/), no retention, no training |
| Mistral | Hosted inference | France | [DPA](https://legal.mistral.ai/terms/data-processing-addendum), zero data retention |
| Staan | Web search | France | [Privacy policy](https://staan.ai/privacy-policy). Zero data retention enabled for API requests; DPO at dpo@qwant.com |

Apple is not a processor. It sells the credit pack as an independent controller and sends the Relay only a signed transaction and refund notifications.
