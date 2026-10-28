# Website releases

## Publish

Requires authorized access to the shared production Terraform state, which includes relay secrets.
See the [website module](https://code.eigin.ai/dev/eigin/-/blob/main/infra/scaleway/modules/website/README.md) for tool prerequisites and infrastructure configuration.

```sh
npm ci
just release website
```

1. Check the printed destination and confirm the upload.
2. Check both languages, navigation and mobile layout in a browser.
3. Keep the successful archive and receipt in `infra/scaleway/website-releases/` together as a known-good release.

The command builds, uploads assets before HTML, and checks served HTML, redirects, asset types and 404 responses. It reads production state without applying infrastructure.

## Verify and recover

Verify a public hostname against the local build that was uploaded:

```sh
WEBSITE_URL=https://www.eigin.ai cargo run --manifest-path tools/Cargo.toml -- website verify
```

- Failed checks produce no successful release receipt. For HTML mismatches, check routing and CDN freshness before retrying.
- Serialize releases: uploads are non-atomic and a failed upload can leave mixed content.
- To roll back content, use a worktree at the known-good source revision and run `just release website`. The command rebuilds source; it does not restore an archive.
- Old assets and removed pages remain in storage. Delete retired paths only through reviewed maintenance.

## Metrics

In the website project's Edge Services pipeline, open **Metrics / Cockpit → Edge Services Overview**.
Counts include assets and bots; they do not represent visits or unique visitors. No browser trackers are used.
