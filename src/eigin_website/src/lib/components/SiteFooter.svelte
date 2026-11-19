<script lang="ts">
  import { FloatingPicker, PickerRow, Icon, LinkButton, type IconName } from "@eigin/ui";
  import { page } from "$app/state";
  import type { SiteContent } from "../content/site";
  import { locales, languageNames, siteHref, type Locale } from "../locales";
  import SiteBrand from "./SiteBrand.svelte";
  let {
    copy,
    locale,
    websiteOrigin = "",
    showLanguagePicker = true,
  }: {
    copy: SiteContent;
    locale: Locale;
    /** Website origin when rendering the shared shell in a separate application. */
    websiteOrigin?: string;
    /** Hide locale switching in applications with English-only content. */
    showLanguagePicker?: boolean;
  } = $props();
  function href(path: string) {
    const resolved = siteHref(path, locale);
    return websiteOrigin ? new URL(resolved, websiteOrigin).href : resolved;
  }
  const pagePath = $derived(page.url.pathname.replace(/^\/[^/]+/, ""));
  const socials: { label: string; href: string; icon: IconName }[] = [
    { label: "LinkedIn", href: "https://www.linkedin.com/company/eigin", icon: "service/linkedin" },
    { label: "Matrix", href: "https://chat.eigin.ai", icon: "service/matrix" },
    { label: "GitLab", href: "https://code.eigin.ai/dev/eigin", icon: "service/gitlab" },
    { label: "GitHub", href: "https://github.com/eigin-ai", icon: "service/github" },
  ];
</script>

<footer class="site-footer">
  <div class="container footer-inner">
    <div class="footer-grid">
      <div class="footer-brand">
        <SiteBrand href={href(`/${locale}/`)} label={copy.homeLabel} />
        <p class="t-body muted">{copy.footer.tagline}</p>
      </div>
      {#each copy.footer.groups as group}
        <nav class="footer-links" aria-label={group.title}>
          <h2 class="t-miniLabel eyebrow">{group.title}</h2>
          {#each group.links as link}
            {#if link.href}
              <a class="t-body" href={href(link.href)}>{link.label}</a>
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
      <div class="footer-controls">
        {#if showLanguagePicker}<nav class="language-links" aria-label={copy.languageNavigation}>
            <FloatingPicker label={copy.languageNavigation} side="top" iconOnly>
              {#snippet trigger()}<Icon name="functional/globe" size={24} />{/snippet}
              {#snippet children(dismiss)}
                {#each locales as language}
                  <PickerRow
                    href={href(`/${language}${pagePath}`)}
                    lang={language}
                    hreflang={language}
                    selected={locale === language}
                    onclick={dismiss}
                  >
                    <span class="t-body">{languageNames[language]}</span>
                  </PickerRow>
                {/each}
              {/snippet}
            </FloatingPicker>
          </nav>
        {/if}
        <nav class="social-links" aria-label={copy.footer.socialNavigation}>
          {#each socials as link}
            <LinkButton {...link} variant="secondary" size="extraSmall" />
          {/each}
        </nav>
      </div>
    </div>
  </div>
</footer>
