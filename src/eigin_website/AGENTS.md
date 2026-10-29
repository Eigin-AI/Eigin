# Eigin website

Static SvelteKit marketing site. Uses the root npm workspace and shared `@eigin/ui` components from `design/web/`.

## Commands

Requires Node >=22.17 and npm >=10. Run from the repository root:

```sh
npm ci
just run web site          # localhost:5174
just stop web site
just logs web site --follow
just build web
npx playwright install chromium webkit
just test website         # checks, static build, browser tests
```

Tests use port 5274; override with `WEBSITE_TEST_PORT`. Check English/Danish and mobile/desktop layouts. Test actual Safari for browser-chrome behavior.

## Editing

- Copy and roadmap data: `src/lib/content/`. Preserve published legal text; label planned features clearly.
- Website components/styles: `src/lib/components/` and `src/lib/styles/`.
- Routes: `src/routes/`; static output: `build/`.
- Use shared design tokens/components. Run `just generate web` after token changes.
- Keep the fixed section palettes, serif Light (300) copy, motion pause controls and reduced-motion support.
- Use `LinkButton` for navigation and `Button` for actions. Locale switching preserves the current page.

## Metadata and assets

`PageHead.svelte` prerenders titles and social metadata. Homepage titles: `Eigin · Personal AI that belongs to you` (English) and `Eigin · Personlig AI, der tilhører dig` (Danish); other pages: `Page name · Eigin`. Shared card copy and public origin live in `src/lib/content/social.json`.

Regenerate committed favicon/social assets with `cargo run --manifest-path tools/Cargo.toml -- website assets`. The bird artwork is shared across locales and needs no fonts. Keep raw fonts out of `static/`.

## Publishing

Authorized operators use `just release website`. It reads shared production state without applying Terraform. See the [release runbook](../../docs/src/runbooks/website-deployment.md) and [hosting module](../../infra/scaleway/modules/website/README.md).
