# Docs releases

Buildkite builds and publishes docs on main webhook builds after Versions and
CI regression tests pass. Fonts are bundled and served from the docs origin.
Verify deployment when **Publish docs** succeeds. The overall build can remain
pending **Run application tests** approval while docs are already published.

## Font setup

Requires permission to distribute the licensed fonts on the docs domain.

1. Open **Settings → CI/CD → Secure files** in the GitLab project.
2. Upload the seven fonts listed in `docs/fonts.json`, using those exact filenames.
   Each file must match its SHA-256 checksum in the manifest.
3. Keep source binaries outside Git. Local builds read `design/assets/fonts/`
   recursively; North East filenames ending in ` copy.otf` are also accepted.

Buildkite downloads these files using `DOCS_GITLAB_TOKEN`, verifies their checksums,
and stages them under `design/assets/fonts/docs/`. Secure Files are accessible
to project members with Developer access or higher; keep project access restricted.

## Build and verify

Requires Rust, mdBook 0.5.3 and mdbook-mermaid 0.17.0.

```sh
just docs build
just docs serve
```

- Generation verifies every font before copying it to the ignored `docs/src/fonts/` directory.
- mdBook includes the fonts in `docs/book/fonts/`. Missing or changed files fail the build.
- Fira Code’s copyright and SIL OFL notice are included at [fonts/FiraCode-LICENSE.txt](../fonts/FiraCode-LICENSE.txt).
- Check font requests in the browser: they should use the docs origin and return `200`.
- Check sidebar subheadings, code blocks and Mermaid diagrams after publishing.

## Update fonts

1. Confirm the licence covers the replacement fonts.
2. Update local files and the matching checksums in `docs/fonts.json` together.
3. Replace the corresponding Secure Files before merging.
4. Build locally and verify the deployed docs after **Publish docs** succeeds.

Website releases and hosting CORS configuration are independent of docs fonts.

## Publishing

- The `eigin/docs-publish` concurrency group permits one upload at a time.
- Before uploading, the job checks the current main SHA and skips stale builds.
- Uploads use `aws s3 sync --delete` to `s3://eigin-docs/` through Scaleway's
  `https://s3.fr-par.scw.cloud` endpoint.
- Font and AWS secrets are restricted to main webhook builds. MR jobs cannot
  access them. See `.buildkite/README.md` for setup and secret policies.
- The build container receives the font token; the upload container receives AWS
  credentials. Neither uses the versions cache. No font-bearing CI artifacts are uploaded.

If publishing fails, fix the cause and trigger a main webhook build. For retries,
confirm the build source still satisfies the webhook-only secret policy.

To stop publishing, pause the pipeline, cancel queued uploads, and drain any
active upload. Keep one publisher active: the concurrency group only coordinates
Buildkite jobs. Verify the live site, fonts, navigation, and Mermaid diagrams
after each deployment.
