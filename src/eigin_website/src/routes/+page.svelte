<script lang="ts">
  import { onMount } from "svelte";
  import { preferredLocale, locales, languageNames } from "#lib/locales.ts";
  import { site } from "#lib/content/site/index.ts";
  onMount(() => window.location.replace(`/${preferredLocale(navigator.languages)}/`));
</script>

<svelte:head><title>Eigin — Choose your language</title></svelte:head>
<main class="language-page">
  <h1>Eigin</h1>
  <nav aria-label={locales.map((locale) => site[locale].languageNavigation).join(" / ")}>
    {#each locales as locale}
      <a href="/{locale}/" lang={locale}>{languageNames[locale]}</a>
    {/each}
  </nav>
</main>
