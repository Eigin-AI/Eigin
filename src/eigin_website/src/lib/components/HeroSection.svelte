<script lang="ts">
  import { Icon, LinkButton } from "@eigin/ui";
  import type { HomeContent } from "#lib/content/home/types.ts";

  let { hero, action }: { hero: HomeContent["hero"]; action: string } = $props();
  const lines = $derived(hero.headline.split("\n"));
</script>

<section id="top" class="hero" data-color-scheme="light" aria-labelledby="headline">
  <div class="container hero-inner">
    <div class="hero-heading">
      <h1 class="t-display hero-title" id="headline">
        <span class="hero-first-line"
          >{lines[0]}<span class="hero-bird hero-bird-flight" aria-hidden="true"
            ><Icon name="illustration/hero-bird" size="fill" /></span
          ></span
        >{#each lines.slice(1) as line}{"\n"}{line}{/each}
      </h1>
    </div>
    <div class="hero-bottom">
      <p class="t-standfirstLarge">{hero.body}</p>
      <div class="hero-cta">
        <LinkButton href="#get" label={action} size="medium" variant="elevated" />
      </div>
    </div>
  </div>
  <span class="hero-bird hero-bird-edge" aria-hidden="true">
    <Icon name="illustration/hero-bird" size="fill" />
  </span>
</section>

<style>
  .hero {
    position: relative;
    overflow: clip;
    --hero-title-size: clamp(48px, 7.2vw, 112px);
  }

  .hero-heading {
    position: relative;
    font-size: var(--hero-title-size);
  }

  .hero-title {
    font-size: inherit;
    color: var(--color-icon-standard-base);
  }

  .hero-first-line {
    display: inline-block;
    position: relative;
  }

  .hero-bird {
    display: flex;
    position: absolute;
    color: var(--color-icon-standard-base);
    pointer-events: none;
  }

  .hero-bird-flight {
    width: 3.6em;
    aspect-ratio: 816 / 764;
    bottom: calc(100% - 0.72em);
    left: calc(100% + 0.3em);
  }

  .hero-bird-edge {
    visibility: hidden;
    opacity: 0;
    height: 110%;
    aspect-ratio: 816 / 764;
    bottom: -20%;
    left: min(calc((100% - 1280px) / 2 - var(--spacing-n16)), 520px);
    transform: translateX(calc(-100% - var(--spacing-n16)));
    transition:
      opacity var(--motion-fast) var(--motion-easing-smooth),
      transform var(--motion-fast) var(--motion-easing-smooth),
      visibility 0s var(--motion-fast);
  }

  @media (prefers-reduced-motion: reduce) {
    .hero-bird-edge {
      transition: none;
    }
  }

  @media (min-width: 641px) {
    .hero-inner {
      /* Reserve room above the headline even in short landscape viewports. */
      padding-top: calc(var(--hero-title-size) * 2.65 + var(--spacing-n48));
    }
  }

  @media (min-width: 1920px) {
    .hero-bird-edge {
      visibility: visible;
      opacity: 1;
      transform: translateX(-100%);
      transition-delay: 0s;
    }
  }

  @media (max-width: 640px) {
    .hero-inner {
      min-height: 0;
    }

    .hero-title {
      white-space: normal;
    }

    .hero-first-line {
      display: inline;
    }

    .hero-bird-flight {
      display: none;
    }
  }
</style>
