# Eigin website

Static SvelteKit marketing site. Keep it independent from the future web app.

## Local development

Use Node.js 22.17 or newer and npm 10 or newer. From the repository root:

```sh
npm ci
just run web site        # http://localhost:5174
just run web gallery     # http://localhost:5173 (also: just run web)
just logs web site --follow
just stop web site
just build web
just test web
npx playwright install chromium webkit
just test website        # checks, static build, browser checks
```

`run` returns once the server starts. Site and gallery can run together.
`stop` and `logs` default to the gallery when no web subtarget is given.
Browser tests use the static production build on port 5274; set
`WEBSITE_TEST_PORT` to override. Screenshots and traces are in `test-results/`.
Use these tests or a browser session to inspect both `/en/` and `/da/`, mobile
and desktop, light and dark. WebKit coverage does not replace real Safari checks.

## Structure

- `src/lib/content/site/`: shared header, navigation, and footer copy per language.
- `src/lib/content/home/`: homepage copy per language.
- `src/lib/content/roadmap/`: editable roadmap data, page copy, and an editing guide.
- `src/lib/content/documents/`: published privacy, terms, contact, and support copy, with Danish Contact and Support translations. Use `<document>/en.ts` and `<document>/da.ts`. Preserve published legal text during layout changes.
- `src/lib/content/trust/`: trust page copy, including the text drawn inside each diagram.
- `src/lib/locales.ts`: supported languages and browser preference selection.
- `src/lib/components/`: website-only header, footer, feature sections, and visual placeholders.
- `src/lib/styles/`: shared site basics, page shell, and homepage layout.
- `src/routes/`: prerendered pages and root browser-language selection.
- `vite.config.ts`: SvelteKit 3 configuration and static adapter.
- `design/web`: shared `@eigin/ui` source; never copy its tokens or components.

Generated design assets are prepared by the run/build/test commands.
After changing `design/tokens.json`, run:

```sh
just generate web
```

Vite watches shared component source and generated CSS. Token source files are
not automatically regenerated. Dependencies use the root workspace lockfile.
The build output is `src/eigin_website/build/`; it needs only static hosting.

Copy and layout follow the owner-approved marketing direction.
The personal demo uses illustrative conversations; Trust diagrams explain data flows.
Decorative motion supports pause controls and reduced motion.
Use the shared `LinkButton` for navigation CTAs and `Button` for actions.
The site uses fixed section palettes, independent of system appearance.
Website serif copy uses the supplied Light (300) face; shared type sizes and
app/gallery weight defaults stay unchanged.
Language links in the footer preserve the current page across explicit locale routes.
The roadmap lives at `/en/roadmap/` and `/da/roadmap/`. Edit its `data.ts` to
update owner-approved entries without changing markup. Planned capabilities must
remain labeled as planned.
Unavailable product destinations stay unlinked. Pricing follows the owner-approved
published offer; team plans are marked as coming soon.
The main CTA leads to the iPhone App Store listing. Company footer links are ordered
Contact, Support, Privacy, Terms, with local routes in both locales. Contact and
Support are translated into Danish. Privacy and Terms stay in English, with an
English-content notice on their Danish routes.
No analytics, signup service, or production deployment is configured here.
Future hosting needs its own opt-in Terraform root/state and release pipeline,
independent of relay and web app deployment. Existing Scaleway resources must
be migrated deliberately rather than recreated.
