<script lang="ts">
  import { LinkButton, Icon, MorphBlob, MorphIntensity, Tag } from "@eigin/ui";
  import SiteHeader from "#lib/components/SiteHeader.svelte";
  import SiteFooter from "#lib/components/SiteFooter.svelte";
  import AnimatedIllustration from "#lib/components/AnimatedIllustration.svelte";
  import FeatureSection from "#lib/components/FeatureSection.svelte";
  import HeroSection from "#lib/components/HeroSection.svelte";
  import Disclosure from "#lib/components/Disclosure.svelte";
  import testflightIcon from "#lib/assets/badges/testflight.png";
  import getVisual from "#lib/assets/get-eigin.webp";
  import type { PageData } from "./$types";
  let { data }: { data: PageData } = $props();
  const copy = $derived(data.copy);
  const site = $derived(data.site);
</script>

<svelte:head>
  <title>{copy.title}</title>
  <meta name="description" content={copy.description} />
  <link rel="alternate" hreflang="en" href="/en/" />
  <link rel="alternate" hreflang="da" href="/da/" />
  <link rel="alternate" hreflang="x-default" href="/" />
</svelte:head>

<a class="skip t-body" href="#main">{site.skip}</a>
<SiteHeader locale={data.locale} copy={site} />
<main id="main">
  <HeroSection hero={copy.hero} action={site.action} />

  <section
    id="why"
    class="mission dark-section"
    data-color-scheme="dark"
    aria-labelledby="mission-title"
  >
    <div class="container section-space mission-statement">
      <h2 class="t-display section-title" id="mission-title">{copy.mission.title}</h2>
      <div class="mission-body t-standfirst">
        {#each copy.mission.paragraphs as paragraph}<p>{paragraph}</p>{/each}
      </div>
    </div>
  </section>

  <FeatureSection feature={copy.personal} />

  <section
    id="private"
    class="privacy dark-section"
    data-color-scheme="dark"
    aria-labelledby="privacy-title"
  >
    <div class="container section-space">
      <div class="content-grid section-heading">
        <div class="section-heading-copy">
          <h2 class="t-display section-title" id="privacy-title">{copy.privacy.title}</h2>
          <p class="t-standfirst section-intro muted">{copy.privacy.body}</p>
        </div>
        <LinkButton
          href={copy.privacy.action.href}
          label={copy.privacy.action.label}
          size="extraSmall"
          variant="outline"
        />
      </div>
      <div class="content-grid promises">
        {#each copy.privacy.promises as promise}
          <div>
            <span class="promise-mark" aria-hidden="true"
              ><Icon name={promise.illustration} size={48} /></span
            >
            <h3 class="t-titleS">{promise.title}</h3>
            <p class="t-body muted">{promise.body}</p>
          </div>
        {/each}
      </div>
    </div>
  </section>

  <FeatureSection feature={copy.team} />

  <section id="pricing" class="pricing" aria-labelledby="pricing-title">
    <div class="container section-space">
      <div class="content-grid section-heading">
        <div class="section-heading-copy">
          <h2 class="t-display section-title" id="pricing-title">{copy.pricing.title}</h2>
          <p class="t-standfirst muted section-intro">{copy.pricing.body}</p>
        </div>
        <LinkButton
          href={copy.pricing.actionHref ?? "mailto:hello@eigin.ai?subject=Eigin%20plans"}
          label={copy.pricing.action}
          size="extraSmall"
          variant="outline"
        />
      </div>
      <div class="content-grid plans">
        {#each copy.pricing.plans as plan}<svelte:element
            this={plan.href ? "a" : "div"}
            class="plan"
            href={plan.href}
          >
            <div class="plan-label">
              <h3 class="t-miniLabel eyebrow muted">{plan.name}</h3>
              {#if plan.status}<Tag label={plan.status} disabled />{/if}
            </div>
            <p class="t-titleM">{plan.price}</p>
            <p class="t-body muted">{plan.detail}</p>
          </svelte:element>{/each}
      </div>
    </div>
  </section>

  <section id="open" class="open-section" aria-labelledby="open-title">
    <div class="container section-space">
      <div class="open-mark" aria-hidden="true"><Icon name="brand/avatar" size="fill" /></div>
      <div class="content-grid section-heading">
        <div class="section-heading-copy">
          <h2 class="t-display section-title" id="open-title">{copy.open.title}</h2>
          <p class="t-standfirst section-intro muted">{copy.open.body}</p>
        </div>
      </div>
      <div class="open-links">
        {#each copy.open.links as link}
          <a class="arrow-link" href={link.href}>
            <span class="t-titleXS arrow-link-label"
              ><span class="arrow-link-text">{link.label}</span><span
                class="arrow-link-icon"
                aria-hidden="true"><Icon name="functional/arrow/up_right" size={16} /></span
              ></span
            >
            <span class="t-body muted">{link.detail}</span>
          </a>
        {/each}
      </div>
    </div>
  </section>

  <section id="get" class="get-section" data-color-scheme="dark" aria-labelledby="get-title">
    <div class="container section-space content-grid get-layout">
      <div class="get-copy">
        <h2 class="t-display section-title" id="get-title">{copy.get.title}</h2>
        <a
          class="get-badge"
          href="https://tally.so/r/rDDpKM"
          target="_blank"
          rel="noopener noreferrer"
          aria-label={copy.get.badge.accessibleLabel}
        >
          <img src={testflightIcon} alt="" width="36" height="36" />
          <span class="get-badge-text">
            <span class="get-badge-eyebrow">{copy.get.badge.eyebrow}</span>
            <span class="get-badge-label">{copy.get.badge.label}</span>
          </span>
        </a>
        <p class="get-beta t-body">{copy.get.instructions}</p>
        <p class="t-body muted get-more">
          {copy.get.more} <a href={copy.get.roadmap.href}>{copy.get.roadmap.label}</a>
        </p>
      </div>
      <AnimatedIllustration class="get-stage" labels={copy.get.motion} controlVariant="open">
        {#snippet children(active)}
          <span class="get-shape" aria-hidden="true">
            <MorphBlob
              tempo={0.25}
              animateEntry={false}
              paused={!active}
              breath={MorphIntensity.full}
              breathPeriod={8}
              color="currentColor"
            />
          </span>
          <img
            class="get-visual"
            src={getVisual}
            alt={copy.get.visual}
            width="1010"
            height="1398"
            loading="lazy"
          />
        {/snippet}
      </AnimatedIllustration>
    </div>
  </section>

  <section id="faq" class="faq-section" aria-labelledby="faq-title">
    <div class="container section-space content-grid faq-layout">
      <div class="faq-heading">
        <h2 class="t-display section-title" id="faq-title">{copy.faq.title}</h2>
        <p class="t-body muted">
          {copy.faq.more} <a href={copy.faq.support.href}>{copy.faq.support.label}</a>
        </p>
      </div>
      <div class="faq-items">
        {#each copy.faq.items as item}
          <Disclosure summary={item.question}>
            <div class="t-body faq-answer">{@html item.answer}</div>
          </Disclosure>
        {/each}
      </div>
    </div>
  </section>
</main>
<SiteFooter locale={data.locale} copy={site} />
