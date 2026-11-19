<script lang="ts">
  /** Responsive section navigation shared by the website and contributor portal. */
  let {
    sections,
    label = "On this page",
    locale = "en",
    contentLanguage = "en",
  }: {
    sections: { id: string; title: string }[];
    label?: string;
    locale?: string;
    contentLanguage?: string;
  } = $props();
  let currentSection = $state<string | null>(null);

  $effect(() => {
    const headings = sections.map((section) => document.getElementById(section.id));
    currentSection = sections[0]?.id ?? null;
    let frame = 0;
    let disposed = false;
    const update = () => {
      frame = 0;
      const threshold = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) + 1;
      let current = headings[0];
      for (const heading of headings) {
        if (
          heading &&
          heading.getBoundingClientRect().top <=
            threshold + (parseFloat(getComputedStyle(heading).scrollMarginTop) || 0)
        )
          current = heading;
      }
      currentSection = current?.id ?? null;
    };
    const schedule = () => {
      if (!disposed && !frame) frame = requestAnimationFrame(update);
    };
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    void document.fonts.ready.then(schedule);
    schedule();
    return () => {
      disposed = true;
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
    };
  });
</script>

{#snippet contents()}
  <nav aria-label={label}>
    <ol class="document-index t-body">
      {#each sections as section}
        <li>
          <a
            href="#{section.id}"
            lang={contentLanguage}
            aria-current={(currentSection ?? sections[0]?.id) === section.id
              ? "location"
              : undefined}>{section.title}</a
          >
        </li>
      {/each}
    </ol>
  </nav>
{/snippet}

<aside class="document-sidebar" lang={locale}>
  <div class="document-desktop-index">
    <p class="t-miniLabel eyebrow">{label}</p>
    {@render contents()}
  </div>
  <details class="document-mobile-index">
    <summary class="t-miniLabel">{label}</summary>
    {@render contents()}
  </details>
</aside>

<style>
  .document-index a[aria-current="location"] {
    color: var(--color-text-standard-base);
    text-decoration: underline;
  }

  .document-sidebar {
    grid-column: span 1;
    position: sticky;
    top: var(--spacing-n128);
    max-height: calc(100svh - var(--spacing-n128) - var(--spacing-n32));
    overflow: auto;
    padding: var(--spacing-n8);
    margin: calc(-1 * var(--spacing-n8));
  }

  .document-index.t-body {
    list-style: none;
    padding: 0;
    margin: var(--spacing-n24) 0 0;
    display: grid;
    gap: var(--spacing-n12);
    line-height: 1.4;
  }

  .document-index a {
    display: inline-block;
    text-decoration: none;
    padding-block: var(--spacing-n4);
  }

  .document-mobile-index {
    display: none;
  }

  @media (max-width: 1023px) {
    .document-sidebar {
      grid-column: 1;
      width: 100%;
      max-width: 65ch;
      position: static;
      max-height: none;
      margin: 0;
      padding: 0;
      overflow: visible;
    }
    .document-desktop-index {
      display: none;
    }
    .document-mobile-index {
      display: block;
      border-block: 1px solid var(--color-border-standard-base);
      padding-block: var(--spacing-n20);
    }
    .document-mobile-index summary {
      cursor: pointer;
      text-transform: uppercase;
    }
    .document-index {
      margin-bottom: var(--spacing-n8);
    }
  }
  @media print {
    .document-sidebar {
      display: none;
    }
  }
</style>
