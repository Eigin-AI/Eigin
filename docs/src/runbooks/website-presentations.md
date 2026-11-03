# Website presentations

The website builds three unlisted, public routes:

- `/present/` — local folder, ZIP, or Markdown player.
- `/present/guide/` — authoring reference and agent workflow.
- `/present/render/` — chrome-free browser screenshot target.

All carry `noindex, nofollow`. They are absent from marketing navigation.
They provide no authentication or confidentiality.

## Author, preview, and share

1. Write `deck.md` beside a `media/` directory. The guide documents slide classes and components.
2. Open `/present/` and choose the folder in Chromium. Edits to Markdown reload every second.
3. For browsers without folder access, build a snapshot with `zip -r deck.zip deck.md media/` and load it locally.
4. Share the deck folder or ZIP with the person presenting it.
5. For PDF, use a saved folder, choose Menu → Export PDF, then Print / Save PDF. Enable background graphics and use 16:9 paper.

Local files never leave the device. Folder recents remain in the legacy
`eigin-present` IndexedDB database, `decks` store. Permissions and records are
origin/browser-local, so a different hostname cannot recover old handles.
Legacy URL recents are hidden; saved directory handles are preserved.
The player ignores `src` and `zip` query parameters. URL-based loading belongs
only to the agent render route.

## Agent self-check

Use the deployed website with local deck files. Requirements: a browser tool
that can supply file bytes and capture screenshots, plus network access to the
website. No website checkout or local web server is required.

1. Package the deck: `zip -r deck.zip deck.md media/`.
2. Open `/present/render/?slide=1` on the public website.
3. Supply the ZIP through the input labelled **Choose a presentation file**.
4. Wait for ready or error, then inspect the screenshot or alert.
5. After edits, rebuild the ZIP and supply fresh bytes through the same input.

With an existing Playwright `page`:

```js
import { readFile } from 'node:fs/promises';

await page.setViewportSize({ width: 1280, height: 720 });
await page.goto('https://www.eigin.ai/present/render/?slide=1');
await page.waitForFunction(() => document.body.dataset.renderStatus === 'idle');
await page.getByLabel('Choose a presentation file').setInputFiles({
  name: 'deck.zip',
  mimeType: 'application/zip',
  buffer: await readFile('deck.zip'),
});
await page.waitForFunction(() => ['ready', 'error'].includes(document.body.dataset.renderStatus));
if (await page.locator('body').getAttribute('data-render-status') === 'error') {
  throw new Error(await page.getByRole('alert').innerText());
}
const total = Number(await page.locator('body').getAttribute('data-total-slides'));
await page.screenshot({ path: 'slide-1.png' });
// Repeat with slide=2 through total. Inspect and revise the authored deck.
```

`slide` is 1-based over flat slide order, including vertical slides. Invalid
values clamp to the available range. `ready` waits for fonts and images;
missing images produce an error. The parent body also exposes
`data-current-slide` and a `data-render-rev` counter during live reload.

The input stays available to automation after rendering. File bytes work with
remote browsers too; the browser needs no access to the agent's filesystem.
The public `/present/guide/#preview` documents the full workflow.

Local files are snapshots. Existing `src` and `zip` URL integrations remain
available on the agent route. URL Markdown watches by default without a selected
slide; `watch=1` enables and `watch=0` disables it.

## Security and limits

The renderer runs in an opaque-origin sandbox with scripts limited to bundled,
nonce-authorized code. Authored HTML/CSS/SVG works; authored scripts, forms,
embedded frames, and plugins requiring same-origin storage do not.
Notes are displayed as text in a parent panel. Fullscreen requires the menu action.
Slide and background changes are instant. Transition query parameters and authored
slide-transition attributes do not enable animation.

Raw CSS and remote media remain author-controlled. Isolation does not prevent
network tracking or CPU/memory abuse. Use trusted decks. Fetches omit credentials.
The agent render route accepts CORS-enabled HTTP(S) sources without an origin allowlist.

- Input: 64 MiB.
- Folder/ZIP: 2,000 files and 256 MiB expanded; ZIP extraction is asynchronous.
- Folder nesting: 32 levels.
- Source request deadline: 20 seconds; frame readiness deadline: 30 seconds.
- Relative media rewriting preserves Markdown images, HTML image sources,
  and background-image attributes. Arbitrary CSS URLs are not rebased.

## Maintenance and verification

Renderer code is in `src/eigin_website/src/lib/present/`. The legacy theme and
frame composer preserve the presentation format; shell styles use the current
website UI. Reveal.js 5.2.1 and fflate 0.8.3 are pinned npm dependencies.

Fonts come from the existing `design/assets/fonts/` source through Vite asset
imports. Font reuse was confirmed by the project owner for this migration.
They are embedded in the lazily loaded renderer so an opaque-origin iframe
needs no font CORS permissions. Do not copy raw fonts into `static/`.
Root-relative icons and the logo preserve legacy URLs. SVG masks are embedded
inside the renderer to avoid cross-origin mask restrictions.

```sh
just test website
# Optional: local compatibility checks without committing private decks.
PRESENTATIONS_DIR=/path/to/presentations WEBSITE_TEST_PORT=18359 \
  npm run test:e2e --workspace @eigin/website -- tests/present --project chromium --project webkit
```

The optional checks cover breakfast-club, evu-pilot-kickoff, and
dtu-digital-tech-summit. Screenshots and Chromium PDF output go to the ignored
Playwright test-results directory. Inspect them when changing theme/layout.

After deployment:

1. Load `/present/guide/` directly and refresh it.
2. Load a representative local folder through `/present/` and refresh its saved `?deck=...` URL.
3. Use `/present/render/?slide=2`, supply a local deck ZIP, wait for ready, and capture a screenshot. Reattach edited files and confirm the preview updates.
4. Verify media, fonts, vertical navigation, notes, and PDF pagination.
5. Check folder permission/reopen behavior in real Chromium and browser chrome/fullscreen in real Safari.

Publishing remains the existing static website release process. No old website
server or runtime is required.

## Shared design-system artwork

`/present/guide/icons/` lists and previews the generated `@eigin/ui` icon registry.
Slides and website components share that registry. Canonical slide URLs are
`/assets/design-icons/<name>.svg`; legacy `/assets/icons/` URLs remain supported.
The website prerenders the canonical SVG endpoints on each build.

For new icons, choose MingCute SVGs from https://icon-sets.iconify.design/mingcute/,
add approved assets under `design/assets/icons/functional/`, retain the licence
attribution, and run `just generate web` before building and deploying the website.
Generated assets are monochrome: masks inherit slide text colour; standalone
SVG images normally render black. Deck-only agents request shared additions from
a website contributor.
