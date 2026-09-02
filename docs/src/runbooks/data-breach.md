# Data breach

What to do when personal data handled by the Relay may have been exposed. The GDPR clock is 72 hours from becoming aware (Art. 33).

## Detect

Breaches surface through [infra alerts](./infra-alerts.md), a [security disclosure](https://code.eigin.ai/dev/eigin/-/blob/main/SECURITY.md), or a notice from a processor. Processors are obliged to tell us without undue delay.

## Contain

1. Rotate the affected secret. Runbooks: [token key](./token-key-rotation.md), [relay key](./relay-key-rotation.md), [grant key](./grant-key-rotation.md), [database key](./database-key-rotation.md).
2. Revoke compromised wallets if credit tokens leaked.
3. Preserve logs in Cockpit before they age out.

## Assess

Record what was exposed, when, and how many wallets were affected. The Relay holds no identities and no content, so the likely categories are credit tokens, wallet balances, and IP addresses in logs. See the [GDPR assessment](../compliance/gdpr.md#personal-data-processed-by-the-relay) for what exists.

## Notify

| Risk to persons | Action |
|---|---|
| Unlikely | Record internally only (Art. 33(5)) |
| Likely | Notify [Datatilsynet](https://www.datatilsynet.dk) within 72 hours (Art. 33) |
| High | Also inform users (Art. 34). The Relay cannot contact users directly, so publish a notice on eigin.ai and in the App |

## Record

Every breach, reported or not, goes in a confidential GitLab issue with the `security` label: facts, effects, and remedial action.
