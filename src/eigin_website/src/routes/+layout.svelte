<script lang="ts">
  import "@eigin/ui/styles/tokens.css";
  import "@eigin/ui/styles/typography.css";
  import "@eigin/ui/styles/fonts.css";
  import "../lib/site.css";
  import { isLocale } from "#lib/locales.ts";
  import { page } from "$app/state";
  import { EiginRoot } from "@eigin/ui";
  let { children } = $props();
  $effect(() => {
    document.documentElement.lang = isLocale(page.params.lang) ? page.params.lang : "en";
  });
</script>

<EiginRoot colorScheme="light">{@render children()}</EiginRoot>
