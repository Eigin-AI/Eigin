<script lang="ts">
  import { iconAssets, LinkButton, SearchField } from "@eigin/ui";
  let query = $state("");
  const entries = Object.entries(iconAssets).sort(([a], [b]) => a.localeCompare(b));
  const matches = $derived(
    entries.filter(([name]) => name.toLowerCase().includes(query.toLowerCase().trim())),
  );
</script>

<svelte:head>
  <title>Presentation icons and illustrations · Eigin</title>
  <meta name="robots" content="noindex, nofollow" />
</svelte:head>

<main class="container section-space t-body">
  <LinkButton
    href="/present/guide/#art"
    label="Back to authoring guide"
    variant="secondary"
    size="small"
  />
  <header>
    <p class="t-miniLabel">Design system / Presentation assets</p>
    <h1 class="t-titleXl">Icons and illustrations</h1>
    <p class="t-standfirst">
      The same generated artwork used by the website, ready for your slides.
    </p>
    <p>
      This catalogue is generated from the design system on every website build. Copy an asset path
      into your deck; the renderer embeds it automatically. Existing legacy asset paths still work.
    </p>
  </header>
  <details class="usage">
    <summary class="t-titleS">Using and adding assets</summary>
    <section aria-label="Using and adding assets">
      <p>For an icon that follows your text colour, use a mask:</p>
      <pre
        class="t-code">{`<span class="icon" style="--shape:url('/assets/design-icons/functional/search.svg')" aria-hidden="true"></span>`}</pre>
      <p>For a monochrome illustration, you can also use an image:</p>
      <pre
        class="t-code">{`<img class="plain" src="/assets/design-icons/illustration/hero-bird.svg" alt="A bird in flight">`}</pre>
      <p>
        Generated assets are monochrome. An image normally renders in black and does not inherit the
        surrounding text colour. Use a mask to match your slide palette.
      </p>
      <p>
        To add an icon, choose it from <a href="https://icon-sets.iconify.design/mingcute/"
          >MingCute on Iconify</a
        >, add its SVG to <code>design/assets/icons/functional/</code>, and run
        <code>just generate web</code> in the Eigin repository. Keep the MingCute licence attribution.
        Review and deploy the website: the icon then appears here and becomes available to both website
        components and slides. A deck-only agent should request this addition from a website contributor.
      </p>
    </section>
  </details>
  <SearchField bind:value={query} placeholder="Search icons and illustrations" />
  <p class="t-note" role="status">{matches.length} of {entries.length} assets</p>
  <ul class="catalogue">
    {#each matches as [name, svg] (name)}
      <li>
        <span class="artwork" aria-hidden="true">{@html svg}</span>
        <h2 class="t-titleXS">{name}</h2>
        <a class="t-code" href={`/assets/design-icons/${name}.svg`}
          >/assets/design-icons/{name}.svg</a
        >
      </li>
    {/each}
  </ul>
  {#if !matches.length}<p>No matching assets. Try another name or category.</p>{/if}
</main>

<style>
  main {
    padding-top: var(--spacing-n32);
    color: var(--color-text-standard-base);
  }
  header,
  section {
    display: grid;
    gap: var(--spacing-n24);
    margin-block: var(--spacing-n32);
    max-width: 65ch;
  }
  header > *,
  section > * {
    margin: 0;
  }
  .usage {
    margin-block: var(--spacing-n32);
    padding-block: var(--spacing-n20);
    border-block: 1px solid var(--color-border-standard-base);
  }
  summary {
    cursor: pointer;
  }
  main > p {
    margin-block: var(--spacing-n24);
  }
  li h2 {
    margin-block: var(--spacing-n16);
  }
  pre {
    overflow-x: auto;
    padding: var(--spacing-n20);
    background: var(--color-surface-standard-elevated);
    border-radius: var(--radius-card);
  }
  .catalogue {
    list-style: none;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 24ch), 1fr));
    gap: var(--spacing-n16);
  }
  li {
    min-width: 0;
    padding: var(--spacing-n24);
    border: 1px solid var(--color-border-standard-base);
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-elevated);
  }
  li h2,
  li a {
    overflow-wrap: anywhere;
  }
  .artwork {
    display: flex;
    align-items: center;
    height: var(--spacing-n64);
  }
  .artwork :global(svg) {
    width: var(--spacing-n64);
    height: var(--spacing-n64);
  }
</style>
