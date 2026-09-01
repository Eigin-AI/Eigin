# Infra alerts

Scaleway Cockpit emails the alerts inbox (`.env` `EIGIN_ALERTS_EMAIL`, else
`EIGIN_SUPPORT_EMAIL`) when a relay alert fires. Rules are Terraform:
`infra/scaleway/monitoring.tf` and `infra/scaleway/rules/*.yaml`.

## Alerts

| Alert | Fires when | Severity |
| --- | --- | --- |
| `RelayWalletCloseOnRefundFailed` | refund kept the user's credits | critical |
| `RelayDebitAfterInferenceFailed` | inference not charged | critical |
| `RelayWalletVanishedAfterDuplicate` | wallet row lost on retry | critical |
| `RelayErrorLogs` | ERROR lines > 10 / 5 min | warning |
| `RelayHostileActivityDetected` | verification failures > 20 / 10 min | warning |
| `RelayContainerCpuHigh` | CPU > 90% for 10 min | warning |
| `RelayContainerMemoryHigh` | memory > 90% for 10 min | warning |
| `RelayDbConnectionsHigh` | DB connections > 50 for 10 min | warning |
| `RelayRestarted` | container cold start / deploy | info |

**Critical** = money moved wrong; reconcile the wallet from the log line's
`wallet_id`, don't restart. **Warning** = check Grafana. **Info** = the deploy
canary; ignore unless you didn't deploy.

## Deploy or change a rule

Edit the YAML, then:

```sh
just infra plan staging    # review the diff
just infra deploy staging  # then production
```

First time only, install the Loki/Mimir providers: `just infra init staging`.

## Verify

- `RelayRestarted` emails on the deploy itself — proves the pipeline.
- Rules: Grafana → Alerting → Alert rules → namespace `eigin-relay`.
- Test the email path directly: `scw cockpit test-alert`.
- Logs: Grafana → Explore → `Scaleway Logs` →
  `{resource_type="serverless_container"}` (SSO login; API keys 401).

## Tune

Too loud or too quiet? Change the threshold or `for:` in the YAML and
redeploy. Keep rules aggregating over `resource_type` — the per-deploy
`resource_name` hashes change. Email-only for now; Cockpit contact points
don't support webhooks via Terraform yet.
