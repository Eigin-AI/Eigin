<script lang="ts">
  import SectionHeading from "#lib/components/SectionHeading.svelte";
  import SiteHeader from "#lib/components/SiteHeader.svelte";
  import SiteFooter from "#lib/components/SiteFooter.svelte";
  import TrustClaim from "#lib/components/TrustClaim.svelte";
  import Disclosure from "#lib/components/Disclosure.svelte";
  import type { TrustLink } from "#lib/content/trust/types.ts";
  import type { PageData } from "./$types";
  let { data }: { data: PageData } = $props();
  const copy = $derived(data.copy);
</script>

{#snippet links(items: TrustLink[])}
  <ul class="trust-links t-body">
    {#each items as link}
      {@const external =
        /^https?:/.test(link.href) && !link.href.startsWith("https://www.eigin.ai")}
      <li>
        <a
          href={link.href}
          target={external ? "_blank" : undefined}
          rel={external ? "noopener" : undefined}>{link.label}</a
        >
      </li>
    {/each}
  </ul>
{/snippet}

{#snippet rowLabel(id: string, title: string)}
  <SectionHeading class="trust-row-label" id="{id}-title" {title} />
{/snippet}

<svelte:head>
  <title>{copy.title}</title>
  <meta name="description" content={copy.description} />
  <link rel="alternate" hreflang="en" href="/en/trust/" />
  <link rel="alternate" hreflang="da" href="/da/trust/" />
  <link rel="alternate" hreflang="x-default" href="/en/trust/" />
</svelte:head>

<a class="skip t-body" href="#main">{data.site.skip}</a>
<SiteHeader locale={data.locale} copy={data.site} />
<main id="main" class="trust-page">
  <div class="container section-space trust-inner">
    <div class="trust-intro">
      <h1 class="t-display trust-title">{copy.heading}</h1>
      <p class="t-standfirstLarge muted">{copy.introduction}</p>
    </div>

    <div class="trust-claims">
      {#each copy.claims as claim}<TrustClaim
          {claim}
          more={copy.more}
          diagrams={copy.diagrams}
        />{/each}
    </div>

    <section id="limits" class="content-grid trust-row" aria-labelledby="limits-title">
      {@render rowLabel("limits", copy.limits.title)}
      <div class="trust-row-content">
        <p class="t-standfirst trust-summary">{copy.limits.introduction}</p>
        <div class="trust-items">
          {#each copy.limits.items as item}
            <Disclosure summary={item.title}>
              <p class="t-body muted">{item.body}</p>
            </Disclosure>
          {/each}
        </div>
      </div>
    </section>

    <section id="responsible" class="content-grid trust-row" aria-labelledby="responsible-title">
      {@render rowLabel("responsible", copy.responsible.title)}
      <div class="trust-row-content">
        <p class="t-standfirst trust-summary">{copy.responsible.body}</p>
        <ul class="trust-people">
          {#each copy.responsible.people as person}
            <li>
              <img src={person.photo} alt="" width="96" height="96" loading="lazy" />
              <div>
                <p class="t-titleXS">{person.name}</p>
                <p class="t-body muted">{person.role}</p>
              </div>
            </li>
          {/each}
        </ul>
      </div>
    </section>

    <section id="transparency" class="content-grid trust-row" aria-labelledby="transparency-title">
      {@render rowLabel("transparency", copy.transparency.title)}
      <div class="trust-row-content">
        <div class="trust-groups">
          {#each copy.transparency.groups as group}
            <div>
              <h3 class="t-miniLabel eyebrow">{group.title}</h3>
              {@render links(group.links)}
            </div>
          {/each}
        </div>
      </div>
    </section>
  </div>
</main>
<SiteFooter locale={data.locale} copy={data.site} />
