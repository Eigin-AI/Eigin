<script lang="ts">
  import authoredGuide from "#lib/present/guide.html?raw";
  import "#lib/styles/document.css";
  const contents = authoredGuide.match(/<ul class="toc">([\s\S]*?)<\/ul>/)?.[1] ?? "";
  const body = authoredGuide.slice(authoredGuide.indexOf('<h2 id="model">'));
  const typography: Record<string, string> = {
    h1: "t-titleXl",
    h2: "t-titleM",
    h3: "t-titleS",
    h4: "t-titleXS",
    code: "t-code",
  };
  const guide = body.replace(
    /<(h[1-4]|code)([^>]*)>/g,
    (_tag, name: string, attributes: string) => {
      const styled = attributes.includes('class="')
        ? attributes.replace('class="', `class="${typography[name]} `)
        : `${attributes} class="${typography[name]}"`;
      return `<${name}${styled}>`;
    },
  );
  import { LinkButton } from "@eigin/ui";
</script>

<svelte:head>
  <title>Presentation authoring guide · Eigin</title>
  <meta name="robots" content="noindex, nofollow" />
</svelte:head>

<main class="presentation-guide document-page">
  <div class="container section-space document-inner">
    <nav class="guide-topbar" aria-label="Presentation navigation">
      <a href="/" class="t-titleS">Eigin</a>
      <LinkButton
        href="/present/"
        label="Open presentation tool"
        variant="secondary"
        size="small"
      />
    </nav>
    <header class="document-header">
      <p class="t-miniLabel">Presentation system / The handbook</p>
      <h1 class="document-title t-display">Deck authoring guide</h1>
      <p class="document-lead t-standfirst">
        Layouts, writing rules, and preview instructions for authors and agents.
      </p>
    </header>
    <div class="document-layout content-grid">
      <nav class="document-sidebar" aria-label="Guide contents">
        <div class="document-desktop-index">
          <h2 class="t-miniLabel">In this guide</h2>
          <ul class="document-index t-body">{@html contents}</ul>
        </div>
        <details class="document-mobile-index">
          <summary class="t-miniLabel">In this guide</summary>
          <ul class="document-index t-body">{@html contents}</ul>
        </details>
      </nav>
      <article class="document-prose t-body">
        <details class="guide-essentials">
          <summary class="t-titleS">Renderer constraints</summary>
          <section aria-label="Renderer constraints">
            <ul>
              <li>
                HTML, inline CSS, and SVG are supported. Authored scripts, embedded frames, and
                forms are blocked. Remote media contacts its host.
              </li>
              <li>
                Input limit: 64 MiB. Folders and ZIPs: at most 2,000 files and 256 MiB expanded.
                Missing images block screenshot readiness.
              </li>
            </ul>
          </section>
        </details>
        {@html guide}
      </article>
    </div>
  </div>
</main>

<style>
  .presentation-guide .document-inner {
    padding-top: var(--spacing-n32);
  }
  .guide-topbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--spacing-n16);
  }
  .guide-topbar > a {
    text-transform: uppercase;
    text-decoration: none;
  }
  .document-header p,
  .document-header h1 {
    margin: 0;
  }
  .document-header .document-title {
    order: 0;
  }
  .document-sidebar h2 {
    margin: 0;
  }
  .guide-essentials {
    padding: var(--spacing-n24);
    border: 1px solid var(--color-border-standard-base);
    border-radius: var(--radius-card);
  }
  .guide-essentials summary {
    cursor: pointer;
  }
  .guide-essentials section {
    margin-top: var(--spacing-n24);
  }
  .presentation-guide :global(h2[id]) {
    margin: var(--spacing-n64) 0 var(--spacing-n24);
    padding-top: var(--spacing-n32);
    border-top: 1px solid var(--color-border-standard-base);
    scroll-margin-top: var(--spacing-n24);
  }
  .presentation-guide :global(h3) {
    margin: var(--spacing-n40) 0 var(--spacing-n20);
  }
  .presentation-guide :global(h4) {
    margin: var(--spacing-n24) 0 var(--spacing-n16);
  }
  .presentation-guide :global(p) {
    margin: 0 0 var(--spacing-n24);
  }
  .presentation-guide :global(ol),
  .presentation-guide :global(article ul) {
    margin-bottom: var(--spacing-n24);
    padding-left: var(--spacing-n24);
  }
  .presentation-guide :global(article li) {
    margin-bottom: var(--spacing-n12);
  }
  .presentation-guide :global(pre) {
    padding: var(--spacing-n24);
    margin-block: var(--spacing-n24);
    background: var(--color-surface-standard-base);
    overflow-x: auto;
    border: 1px solid var(--color-border-standard-base);
    border-radius: var(--radius-card);
  }
  .presentation-guide :global(code) {
    overflow-wrap: anywhere;
  }
  .presentation-guide :global(table) {
    display: block;
    overflow-x: auto;
    border-collapse: collapse;
    margin-block: var(--spacing-n24);
  }
  .presentation-guide :global(td),
  .presentation-guide :global(th) {
    padding: var(--spacing-n16);
    border-bottom: 1px solid var(--color-border-standard-base);
    text-align: left;
    vertical-align: top;
  }
  .presentation-guide :global(.warn) {
    margin-block: var(--spacing-n24);
    padding: var(--spacing-n24);
    border-left: 2px solid var(--color-text-standard-base);
    background: var(--color-surface-standard-base);
  }
  .presentation-guide :global(.cover-example) {
    display: block;
    width: 100%;
    height: auto;
    border-radius: var(--radius-card);
    margin-block: var(--spacing-n24);
  }
  .presentation-guide :global(svg) {
    max-width: 100%;
  }
  @media (max-width: 1023px) {
    .document-sidebar {
      padding-bottom: 0;
    }
    .document-index {
      columns: 2;
      display: block;
    }
    .document-index :global(li) {
      break-inside: avoid;
      padding-bottom: var(--spacing-n8);
    }
  }
  @media (max-width: 600px) {
    .document-index {
      columns: 1;
    }
  }
</style>
