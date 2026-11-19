<script lang="ts">
  import { FloatingPicker, LinkButton, PickerRow } from "@eigin/ui";
  import type { Snippet } from "svelte";
  import { page } from "$app/state";
  import { siteHref, type Locale } from "../locales";
  import type { SiteContent } from "../content/site";
  import SiteBrand from "./SiteBrand.svelte";
  let {
    locale,
    copy,
    websiteOrigin = "",
    homeHref,
    showGetAction = true,
    accountAction,
    brandName = "Eigin",
    externalLinksNewTab = false,
  }: {
    locale: Locale;
    copy: SiteContent;
    /** Website origin when rendering the shared shell in a separate application. */
    websiteOrigin?: string;
    /** Application home; defaults to the website locale homepage. */
    homeHref?: string;
    /** Keep the marketing CTA on website pages. */
    showGetAction?: boolean;
    /** Optional application account control. */
    accountAction?: Snippet;
    /** Visible application name beside the Eigin mark. */
    brandName?: string;
    /** Open absolute navigation destinations in another tab. */
    externalLinksNewTab?: boolean;
  } = $props();
  function href(path: string) {
    const resolved = siteHref(path, locale);
    return websiteOrigin ? new URL(resolved, websiteOrigin).href : resolved;
  }
  const sectionIds = $derived(
    copy.navigation.filter((link) => link.href.startsWith("#")).map((link) => link.href.slice(1)),
  );
  // The homepage section currently sitting under the header, if it's one the menu links to.
  let currentSection: string | undefined = $state();

  $effect(() => {
    if (page.url.pathname !== `/${locale}/`) return;
    const header = document.querySelector<HTMLElement>(".site-header");
    let frame = 0;
    const update = () => {
      frame = 0;
      const line = (header?.offsetHeight ?? 0) + 1;
      currentSection = sectionIds.find((id) => {
        const box = document.getElementById(id)?.getBoundingClientRect();
        return box !== undefined && box.top <= line && box.bottom > line;
      });
    };
    const schedule = () => (frame ||= requestAnimationFrame(update));
    update();
    addEventListener("scroll", schedule, { passive: true });
    addEventListener("hashchange", schedule);
    return () => {
      removeEventListener("scroll", schedule);
      removeEventListener("hashchange", schedule);
      cancelAnimationFrame(frame);
    };
  });

  function isCurrent(href: string) {
    return href.startsWith("#") ? currentSection === href.slice(1) : page.url.pathname === href;
  }
</script>

<header class="site-header">
  <div class="container header-inner">
    <SiteBrand href={homeHref ?? href(`/${locale}/`)} label={copy.homeLabel} name={brandName} />
    <nav class="desktop-nav" aria-label={copy.mainNavigation}>
      {#each copy.navigation as link}
        <a
          class="t-navTab"
          href={href(link.href)}
          target={externalLinksNewTab && /^https?:/.test(link.href) ? "_blank" : undefined}
          rel={externalLinksNewTab && /^https?:/.test(link.href) ? "noopener" : undefined}
          >{link.label}</a
        >
      {/each}
    </nav>
    <div class="header-actions">
      {#if accountAction}{@render accountAction()}{/if}
      {#if showGetAction}<div class="header-cta">
          <LinkButton
            href={href(`/${locale}/#get`)}
            label={copy.action}
            size="extraSmall"
            variant="spot"
          />
        </div>
      {/if}
      <div class="mobile-menu">
        <FloatingPicker label={copy.menu}>
          {#snippet trigger()}<span class="t-buttonSmall">{copy.menu}</span>{/snippet}
          {#snippet children(dismiss)}
            {#each copy.navigation as link}
              <PickerRow
                href={href(link.href)}
                target={externalLinksNewTab && /^https?:/.test(link.href) ? "_blank" : undefined}
                rel={externalLinksNewTab && /^https?:/.test(link.href) ? "noopener" : undefined}
                selected={isCurrent(link.href)}
                onclick={dismiss}><span class="t-navTab">{link.label}</span></PickerRow
              >
            {/each}
            {#if showGetAction}<LinkButton
                href={href(`/${locale}/#get`)}
                label={copy.action}
                size="extraSmall"
                variant="spot"
                onclick={dismiss}
              />{/if}
          {/snippet}
        </FloatingPicker>
      </div>
    </div>
  </div>
</header>
