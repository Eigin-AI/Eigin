# Contributor portal hosting

`just infra deploy production` builds and deploys the Node app to `https://contribute.eigin.ai`. Hosting exists only in the production workspace. Call #443 accepts private submissions until its deadline. Reviewer access is restricted to GitLab ID 5. Rehearse submissions and publication locally; never seed the production database.

## First deployment (operator only)

Use the shared [remote state](../../../../docs/src/runbooks/terraform-remote-state.md), Terraform, authenticated `scw`, a running Docker daemon, Node 24, `just`, Rust and curl. Serialize releases and infrastructure changes. Review the **entire** root plan each time: relay and website share this state. After a successful apply, the production recipe checks the candidate digest, migrates the database, switches the container and verifies the public service. Staging skips this step.

1. Supply `CONTRIBUTORS_GITLAB_CLIENT_ID` and `CONTRIBUTORS_GITLAB_CLIENT_SECRET` in the untracked root `.env`. Use the registered `read_user` app with callback `https://contribute.eigin.ai/auth/callback`. Local development uses the same keys. Register `http://localhost:5176/auth/callback` on the same GitLab application as a second redirect URI.
2. Initialize the production workspace and review `just infra plan production`. The production infra recipes build and check the portal locally, then stage only runtime files and dependency manifests into the Docker context. Terraform's Docker provider builds and pushes a Linux AMD64 image on apply when the context changes. The SHA-256 registry digest goes directly to the release output. The initial apply also provisions the private service and job definitions. Both compute minima are zero; storage and logs can still incur charges.
3. Read the nonsecret `hostname` field with `TF_WORKSPACE=production terraform -chdir=infra/scaleway output -json contributor_release`. At the authoritative DNS provider create a CNAME from `contribute.eigin.ai` to that hostname. Bind `contribute.eigin.ai` to the portal in the Scaleway console and verify certificate issuance before release. DNS and custom-domain binding are managed outside this Terraform module. Check the daily 03:17 UTC cleanup job after migration.
4. On first provisioning, the deploy may stop at the DNS/TLS check until the domain is bound. After binding it, rerun the production deploy. It runs and waits for the migration job, then updates the service to the same digest and checks HTTPS, OAuth redirect, public brief and denied anonymous review. It updates cleanup only after verification. A failed first release restores private access; a failed migration never switches the service. A release requires live support for digest references in both Jobs and Containers. Stop if either API rejects the reference; do not substitute `latest`.

## Subsequent releases and rollback

For changed code, review `just infra plan production`, then run `just infra deploy production`. No separate promotion command is needed. A ready, public service already running the candidate digest is left alone. Failure after apply leaves the infrastructure changes in state and reports a failed deployment. Keep the migration compatible with the previous app; image rollback never reverses SQL. After successful verification find the active and previous digest in `infra/scaleway/contributor-releases/*.json`. Retain known-good images and the accompanying `.brief` files: each records the expected public brief status for its digest. Deploy and rollback both require the expected status for the previous public digest. Restore missing receipts from release records. For deployments predating `.brief` receipts, check the verified image and its release history, then save `200` (call open) or `404` (pre-launch) without a newline in `<64-digit-digest>.brief` alongside the receipt. Never infer the expected status from a failing live request. To switch back: `just rollback-contributor sha256:<known-good-digest>`. If automatic recovery fails, inspect the service and job runs before retrying. Check a subsequent Terraform plan preserves the active service image, privacy, and job images.

## Launch checks

- Complete real GitLab sign-in and sign-out. Confirm `/calls/tool-safety` returns 200 and links to issue #443. Anonymous review must return 404. Sign in as GitLab ID 5 and verify the review dashboard; never submit rehearsal data to production.
- Use direct managed HTTPS and zero to one replica. The per-process sign-in limiter resets on restart. Verify that the proxy appends the real client address last (`XFF_DEPTH=1`) on **both** hostnames, that untrusted forwarding headers cannot change the limit, and that a second independent connection retains its allowance. Verify before inviting anyone. Keep the service private if these checks fail. Revisit ingress-wide limiting before increasing the replica cap.
- Verify runtime can read/write application records but cannot change schema or administer SQL; the migration identity can apply migrations. [IAM permissions](https://www.scaleway.com/en/docs/serverless-sql-databases/how-to/manage-permissions/) are project-scoped: keep unrelated databases out of this project. Both connections use `sslmode=verify-full`. Only the migration job receives schema-changing credentials. DB URLs and OAuth values are sensitive in shared Terraform state. Rotate database keys by reviewed replacement before the one-year expiry. After rotation verify both jobs and sign-in; update OAuth credentials via hosting, never the image.
- Check platform container logs and job run history, including failed migrations and cleanup. Verify logged request metadata does not include cookies, OAuth callback query strings or submission data. Do not enable HTTP body/header tracing. Health probes hit `/healthz` without querying SQL.
- SQL [backups](https://www.scaleway.com/en/docs/serverless-sql-databases/how-to/manage-backups/) run daily and are retained seven days. After the first backup use **Create database from backup**; never restore over the serving database during a drill. Verify the migration ledger, expected rows and permissions without printing personal data. Record backup timestamp, restore time and outcome, then remove the disposable copy. An app rollback is preferable when data recovery is unnecessary.

## Local package check

```sh
npm ci
just generate web
just test contributor
docker build --platform linux/amd64 -t contributor-local:check -f src/eigin_contributors/Dockerfile .
src/eigin_contributors/scripts/smoke-image.sh contributor-local:check
```

The smoke check runs entirely on an isolated Docker network with PostgreSQL 16, applies migrations twice, prunes expired attempts and checks public and closed routes. It removes test containers and volumes on exit. Use `just test contributor postgres` for the separate app/database rehearsal suite.
