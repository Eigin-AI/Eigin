<script lang="ts">
  import DocumentIndex from "./DocumentIndex.svelte";
  import PageHead from "./PageHead.svelte";
  import { LinkButton } from "@eigin/ui";
  import SiteHeader from "./SiteHeader.svelte";
  import SiteFooter from "./SiteFooter.svelte";
  import ReachPageContent from "./ReachPageContent.svelte";
  import { documentHtml, type DocumentSlug } from "#lib/content/documents/index.ts";
  import type { DocumentContent } from "#lib/content/documents/types.ts";
  import type { SiteContent } from "#lib/content/site/types.ts";
  import type { Locale } from "#lib/locales.ts";
  import "#lib/styles/document.css";

  let {
    content,
    slug,
    locale,
    site,
  }: {
    content: DocumentContent;
    slug: DocumentSlug;
    locale: Locale;
    site: SiteContent;
  } = $props();
  const contentsLabel = $derived(locale === "da" ? "På denne side" : "On this page");
  const legal = $derived(slug === "privacy" || slug === "terms");
</script>

<PageHead
  title={`${content.title} · Eigin`}
  description={content.description}
  {locale}
  path={`${slug}/`}
/>

<a class="skip t-body" href="#main">{site.skip}</a>
<SiteHeader {locale} copy={site} />
<main id="main" class:document-page={legal} class:reach-page={!legal} lang={legal ? "en" : locale}>
  {#if slug === "contact" || slug === "support"}
    <ReachPageContent {content} {slug} {locale} />
  {:else}
    <div class="container section-space document-inner">
      <header class="document-header">
        {#if locale === "da"}
          <p class="document-language t-note" lang="da">Indholdet på denne side er på engelsk.</p>
        {/if}
        {#if content.updated}
          <p class="document-updated t-miniLabel">{content.updated}</p>
        {/if}
        <h1 class="document-title t-display">{content.title}</h1>
        {#if slug === "privacy"}
          <p class="document-related t-body">
            Read about our privacy and safety principles on the <a href="/{locale}/trust/"
              >Trust page</a
            >.
          </p>
        {/if}
      </header>
      <div class="content-grid document-layout">
        <DocumentIndex sections={content.sections} label={contentsLabel} {locale} />
        <article class="document-prose t-body" aria-label={content.title}>
          <div class="document-introduction">
            {#each content.introduction as block, index}
              {#if block.action}
                <div class="document-action">
                  <LinkButton
                    href={block.action.href}
                    label={block.action.label}
                    size="medium"
                    variant="spot"
                  />
                </div>
              {:else}
                <div class:document-lead={index === 0} class:t-standfirst={index === 0}>
                  {@html documentHtml(block.html, locale)}
                </div>
              {/if}
            {/each}
          </div>
          {#each content.sections as section}
            <section class="document-section" aria-labelledby={section.id}>
              <h2 class="t-titleS" id={section.id} tabindex="-1">{section.title}</h2>
              <div class="document-section-copy">{@html documentHtml(section.html, locale)}</div>
            </section>
          {/each}
        </article>
      </div>
    </div>
  {/if}
</main>
<SiteFooter {locale} copy={site} />
