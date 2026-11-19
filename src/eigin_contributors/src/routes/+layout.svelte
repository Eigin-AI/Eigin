<script lang="ts">
  import { page } from "$app/state";
  import favicon from "@eigin/website/favicon.svg?url";
  import faviconPng from "@eigin/website/favicon-32.png?url";
  import touchIcon from "@eigin/website/apple-touch-icon.png?url";
  import "@eigin/ui/styles/tokens.css";
  import "@eigin/ui/styles/typography.css";
  import "@eigin/ui/styles/fonts.css";
  import "@eigin/website/styles.css";
  import { EiginRoot, LinkButton, Button } from "@eigin/ui";
  import SiteHeader from "@eigin/website/SiteHeader.svelte";
  import SiteFooter from "@eigin/website/SiteFooter.svelte";
  import { site } from "@eigin/website/content";
  import "#lib/site.css";
  import { typeProperties } from "#lib/type-properties.ts";
  let { children, data } = $props();
  const portalCopy = $derived({
    ...site.en,
    homeLabel: "Eigin contributors",
    navigation: [
      { label: "Open Calls", href: "/#open-calls" },
      { label: "About", href: "/guides/process" },
      { label: "Specs", href: "/guides/spec" },
      ...(data.canReview ? [{ label: "Review", href: "/review" }] : []),
    ],
  });
</script>

<svelte:head
  ><title>Contribute · Eigin</title><meta name="robots" content="noindex" />
  <link rel="icon" type="image/svg+xml" href={favicon} />
  <link rel="icon" type="image/png" sizes="32x32" href={faviconPng} />
  <link rel="apple-touch-icon" sizes="180x180" href={touchIcon} />
</svelte:head>
<EiginRoot colorScheme="light">
  <a class="skip t-body" href="#main">Skip to content</a>
  <SiteHeader
    locale="en"
    copy={portalCopy}
    homeHref="/"
    showGetAction={false}
    brandName="Eigin"
    externalLinksNewTab
  >
    {#snippet accountAction()}
      {#if data.user}
        <form method="POST" action="/auth/logout">
          <Button label="Sign out" size="extraSmall" variant="outline" />
        </form>
      {:else}
        <div data-sveltekit-reload data-sveltekit-preload-data="false">
          <LinkButton
            href={"/auth/gitlab?returnTo=" +
              encodeURIComponent(
                page.url.pathname + page.url.search + page.url.hash,
              )}
            label="Sign in"
            size="extraSmall"
            variant="outline"
          />
        </div>
      {/if}
    {/snippet}
  </SiteHeader>
  <main id="main" class="contributor-page" style={typeProperties}>
    {@render children()}
  </main>
  <SiteFooter
    locale="en"
    copy={site.en}
    websiteOrigin="https://www.eigin.ai"
    showLanguagePicker={false}
  />
</EiginRoot>
