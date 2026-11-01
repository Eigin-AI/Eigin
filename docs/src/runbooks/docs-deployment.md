# Docs releases

Docs CI builds and publishes on `main`. Fonts are bundled with the book and
served from the docs origin.

## Font setup

Requires permission to distribute the licensed fonts on the docs domain.

1. Open **Settings → CI/CD → Secure files** in the GitLab project.
2. Upload the seven fonts listed in `docs/fonts.json`, using those exact filenames.
   Each file must match its SHA-256 checksum in the manifest.
3. Keep source binaries outside Git. Local builds read `design/assets/fonts/`
   recursively; North East filenames ending in ` copy.otf` are also accepted.

CI downloads only these files using `CI_JOB_TOKEN`, verifies their checksums,
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
4. Build locally and verify the deployed docs after CI completes.

Website releases and hosting CORS configuration are independent of docs fonts.
