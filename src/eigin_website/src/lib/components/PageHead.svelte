<script lang="ts">
  import social from "#lib/content/social.json";
  import type { Locale } from "#lib/locales.ts";

  let {
    title,
    description,
    locale,
    path = "",
    root = false,
  }: {
    title: string;
    description: string;
    locale: Locale;
    path?: string;
    root?: boolean;
  } = $props();
  const canonical = $derived(`${social.origin}${root ? "/" : `/${locale}/${path}`}`);
  const image = $derived(`${social.origin}/social/${locale}.png`);
  const alternate = $derived(locale === "en" ? "da" : "en");
</script>

<svelte:head>
  <title>{title}</title>
  <meta name="description" content={description} />
  <link rel="canonical" href={canonical} />
  <link rel="alternate" hreflang="en" href={`${social.origin}/en/${path}`} />
  <link rel="alternate" hreflang="da" href={`${social.origin}/da/${path}`} />
  <link
    rel="alternate"
    hreflang="x-default"
    href={`${social.origin}/${path ? `en/${path}` : ""}`}
  />
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Eigin" />
  <meta property="og:title" content={title} />
  <meta property="og:description" content={description} />
  <meta property="og:url" content={canonical} />
  <meta property="og:locale" content={social[locale].locale} />
  <meta property="og:locale:alternate" content={social[alternate].locale} />
  <meta property="og:image" content={image} />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:alt" content={social[locale].imageAlt} />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={title} />
  <meta name="twitter:description" content={description} />
  <meta name="twitter:image" content={image} />
  <meta name="twitter:image:alt" content={social[locale].imageAlt} />
</svelte:head>
