<script lang="ts">
  import { page } from "$app/state";
  import type { SiteContent } from "../content/site";
  import { locales, languageNames, siteHref, type Locale } from "../locales";
  import SiteBrand from "./SiteBrand.svelte";
  let { copy, locale }: { copy: SiteContent; locale: Locale } = $props();
  const pagePath = $derived(page.url.pathname.replace(/^\/[^/]+/, ""));
  const socials = [
    { label: "Matrix", href: "https://chat.eigin.ai" },
    { label: "GitLab", href: "https://code.eigin.ai/dev/eigin" },
    { label: "GitHub", href: "https://github.com/eigin-ai" },
    { label: "LinkedIn", href: "https://www.linkedin.com/company/eigin" },
  ];
</script>

<footer class="site-footer">
  <div class="container footer-inner">
    <div class="footer-grid">
      <div class="footer-brand">
        <SiteBrand href="/{locale}/" label={copy.homeLabel} />
        <p class="t-body muted">{copy.footer.tagline}</p>
      </div>
      {#each copy.footer.groups as group}
        <nav class="footer-links" aria-label={group.title}>
          <h2 class="t-miniLabel eyebrow">{group.title}</h2>
          {#each group.links as link}
            {#if link.href}
              <a class="t-body" href={siteHref(link.href, locale)}>{link.label}</a>
            {:else}
              <span class="t-body muted"
                >{link.label}<small class="t-descriptionSmall coming-soon"
                  >{copy.footer.comingSoon}</small
                ></span
              >
            {/if}
          {/each}
        </nav>
      {/each}
    </div>
    <div class="footer-bottom">
      <p class="t-miniLabel muted">{copy.footer.copyright}</p>
      <nav class="language-links" aria-label={copy.languageNavigation}>
        {#each locales as language}
          <a
            class="t-body"
            href="/{language}{pagePath}"
            lang={language}
            hreflang={language}
            aria-current={locale === language ? "page" : undefined}>{languageNames[language]}</a
          >
        {/each}
      </nav>
      <nav class="social-links" aria-label={copy.footer.socialNavigation}>
        {#each socials as link}<a class="t-description" href={link.href}>{link.label}</a>{/each}
      </nav>
    </div>
  </div>
</footer>
