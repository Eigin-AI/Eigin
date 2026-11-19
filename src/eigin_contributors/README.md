# Contributor portal

## Run locally

1. Start Docker and run `npm ci`.
2. Run `just run web contributor`. It starts PostgreSQL 16 for this checkout, applies migrations, and serves `http://localhost:5176`.

The database container is reused across runs and binds to a Docker-assigned loopback port. `just stop web contributor` stops the website; its database stays available. Removing the Docker container and its volume deletes the local data. Existing databases from earlier setups are left untouched and are not imported automatically.

For sign-in, set `CONTRIBUTORS_GITLAB_CLIENT_ID` and `CONTRIBUTORS_GITLAB_CLIENT_SECRET` in the root `.env`. Register `http://localhost:5176/auth/callback` with the GitLab OAuth app (`read_user`). Set `CONTRIBUTORS_REVIEWER_GITLAB_IDS` to a comma-separated list of numeric IDs from `/account`, then restart.

## Calls

Add `content/calls/<slug>/call.json` and `brief.md`. The slug must match the directory. Set `publicListing: true` to list the call. Use `<!-- foldouts -->` and `<!-- end-foldouts -->` for disclosures; the first heading inside sets the item depth.

The first submission freezes dates, awards, and agreement versions. Each account can save up to 20 versions per call. A public call moves to Previous calls at closure. In `/review`, select two different submissions and confirm the exact revisions. Results remain private until explicitly published in a separate step.

## Verify

- `just test contributor` checks the app and Markdown content.
- `just test contributor postgres` starts and removes a disposable PostgreSQL 16 container with fresh credentials, and runs the database, browser, and production smoke tests. Install Playwright Chromium first (`npx playwright install chromium`).

## Deployment

See the [production deployment and rollback runbook](../../infra/scaleway/modules/contributor/README.md).

Inject `ORIGIN`, `DATABASE_URL`, `GITLAB_CLIENT_ID`, `GITLAB_CLIENT_SECRET`, and optionally `REVIEWER_GITLAB_IDS` through the hosting environment. Apply migrations before serving traffic. Schedule `npm run db:prune-oauth --workspace @eigin/contributors` (e.g. every 10 minutes). Production uses the application limiter with at most one replica and trusts one verified proxy hop. Revisit ingress-wide limiting before adding replicas.

Sign-in uses two HttpOnly, SameSite=Lax cookies (Secure on HTTPS): a ten-minute OAuth browser binding and a seven-day session. Participation terms v1.0 describe privacy and payment handling.

Production lists approved calls, including #443. Real submissions explicitly sign the Individual CLA v1.0 and accept participation terms v1.0. Only configured GitLab reviewer IDs have review access. Rehearsal consent is not a signed CLA. Git publication, email, and payments remain manual.
