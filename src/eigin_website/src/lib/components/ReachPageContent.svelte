<script lang="ts">
  import SectionHeading from "./SectionHeading.svelte";
  import { LinkButton } from "@eigin/ui";
  import { documentHtml } from "#lib/content/documents/index.ts";
  import type { DocumentContent } from "#lib/content/documents/types.ts";
  import type { Locale } from "#lib/locales.ts";
  import daniel from "#lib/assets/team/daniel-rothmann.jpg";
  import therkel from "#lib/assets/team/therkel-sand-therkelsen.jpg";
  import "#lib/styles/reach.css";

  let {
    content,
    slug,
    locale,
  }: {
    content: DocumentContent;
    slug: "contact" | "support";
    locale: Locale;
  } = $props();
  const people = $derived([
    {
      name: "Daniel Rothmann",
      role: locale === "da" ? "Medstifter og CTO" : "Co-founder and CTO",
      photo: daniel,
    },
    {
      name: "Therkel Sand Therkelsen",
      role: locale === "da" ? "Medstifter og CEO" : "Co-founder and CEO",
      photo: therkel,
    },
  ]);
</script>

{#snippet sectionCopy(section: DocumentContent["sections"][number])}
  <h2 class="t-titleS" id={section.id} tabindex="-1">{section.title}</h2>
  <div class="document-section-copy">{@html documentHtml(section.html, locale)}</div>
{/snippet}

<section
  class="reach-hero"
  class:reach-contact={slug === "contact"}
  class:reach-support={slug === "support"}
  aria-labelledby="reach-title"
>
  <div class="container content-grid reach-hero-inner">
    <div class="reach-copy">
      <h1 class="document-title t-display" id="reach-title">{content.title}</h1>
      <div class="document-prose reach-introduction t-body">
        {#each content.introduction as block, index}
          <div class:reach-channel={Boolean(block.label)}>
            {#if block.label}
              <h2 class="reach-channel-label t-miniLabel eyebrow">{block.label}</h2>
            {/if}
            {#if block.action}
              <div class="reach-action">
                <LinkButton
                  href={block.action.href}
                  label={block.action.label}
                  size="medium"
                  variant="spot"
                />
              </div>
            {:else}
              <div
                class:document-lead={index === 0 || (slug === "support" && index === 1)}
                class:t-standfirst={index === 0 || (slug === "support" && index === 1)}
              >
                {@html documentHtml(block.html, locale)}
              </div>
            {/if}
          </div>
        {/each}
      </div>
    </div>
    {#if slug === "support"}
      <div class="reach-help-panel document-prose t-body">
        {#each content.sections.filter((section) => section.id === "what-to-include") as section}
          <section aria-labelledby={section.id}>
            {@render sectionCopy(section)}
          </section>
        {/each}
      </div>
    {/if}
  </div>
</section>
{#if slug === "contact"}
  <div class="container content-grid reach-contact-details">
    <SectionHeading
      class="reach-details-label"
      headingClass="reach-details-title"
      title={locale === "da" ? "Andre måder at få fat i os" : "More ways to reach us"}
    />
    <div class="reach-details document-prose t-body">
      {#each content.sections as section}
        <section class="reach-detail" aria-labelledby={section.id}>
          <h3 class="t-titleS" id={section.id} tabindex="-1">{section.title}</h3>
          <div class="reach-detail-content">
            {#if section.id === "company"}
              <section class="reach-people" aria-label={locale === "da" ? "Teamet" : "The team"}>
                <p class="t-body reach-team-location">
                  {locale === "da"
                    ? "Vi er et distribueret team med base i København og Aarhus."
                    : "We're a distributed team based in Copenhagen and Aarhus."}
                </p>
                <div class="reach-portraits">
                  {#each people as person}
                    <figure class="reach-person">
                      <img src={person.photo} alt="" width="640" height="641" />
                      <figcaption>
                        <p class="t-titleXS">{person.name}</p>
                        <p class="t-body">{person.role}</p>
                      </figcaption>
                    </figure>
                  {/each}
                </div>
              </section>
            {/if}
            <div class="document-section-copy">{@html documentHtml(section.html, locale)}</div>
          </div>
        </section>
      {/each}
    </div>
  </div>
{/if}

{#if slug === "support"}
  <div class="container content-grid reach-support-other">
    {#each content.sections.filter((section) => section.id !== "what-to-include") as section}
      <section class="document-prose t-body" aria-labelledby={section.id}>
        {@render sectionCopy(section)}
      </section>
    {/each}
  </div>
{/if}
