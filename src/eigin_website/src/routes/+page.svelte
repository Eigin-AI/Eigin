<script lang="ts">
  import { Icon, LinkButton } from "@eigin/ui";
  import { locales, languageNames } from "#lib/locales.ts";
  import { site } from "#lib/content/site/index.ts";
</script>

<svelte:head><title>Eigin — Choose your language / Vælg sprog</title></svelte:head>
<main class="language-page">
  <div class="language-content">
    <span class="language-brand" aria-hidden="true"><Icon name="brand/avatar" size={64} /></span>
    <h1 class="t-display">Eigin</h1>
    <p class="t-body">Choose your language <span lang="da">/ Vælg sprog</span></p>
    <nav aria-label={locales.map((locale) => site[locale].languageNavigation).join(" / ")}>
      {#each locales as locale}
        <span lang={locale}>
          <LinkButton
            href="/{locale}/"
            label={languageNames[locale]}
            variant="outline"
            size="small"
          />
        </span>
      {/each}
    </nav>
  </div>
</main>

<style>
  .language-page {
    display: grid;
    place-items: center;
    min-height: 100svh;
    padding: var(--spacing-n24);
    background: var(--color-surface-impact-base);
    color: var(--color-icon-standard-base);
  }
  .language-content {
    display: grid;
    justify-items: center;
    gap: var(--spacing-n24);
    text-align: center;
  }
  .language-brand {
    display: flex;
  }
  h1 {
    text-transform: uppercase;
  }
  nav {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: var(--spacing-n16);
  }
</style>
