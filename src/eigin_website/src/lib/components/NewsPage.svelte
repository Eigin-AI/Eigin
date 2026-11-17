<script lang="ts">
  import { Icon } from "@eigin/ui";
  import PageHead from "./PageHead.svelte";
  import SiteHeader from "./SiteHeader.svelte";
  import SiteFooter from "./SiteFooter.svelte";
  import type { loadNews } from "#lib/content/news/page.ts";
  import "#lib/styles/news.css";

  let { data }: { data: Awaited<ReturnType<typeof loadNews>> } = $props();
  const copy = $derived(data.copy);
  const dateFormat = $derived(
    new Intl.DateTimeFormat(data.locale, { dateStyle: "long", timeZone: "UTC" }),
  );
</script>

<PageHead
  title={`${data.isArticle ? data.post?.title : copy.heading} · Eigin`}
  description={data.isArticle ? data.post!.description : copy.description}
  locale={data.locale}
  path={data.path}
  metadata={data.isArticle
    ? { type: "article", publishedAt: data.post!.date }
    : { type: "website" }}
/>
<svelte:head>
  <link
    rel="alternate"
    type="application/rss+xml"
    title={`${copy.heading} · Eigin`}
    href={`/${data.locale}/news/rss.xml`}
  />
</svelte:head>

{#snippet postList()}
  <nav aria-label={copy.posts}>
    <ul class="news-posts t-body">
      {#each data.posts as post (post.slug)}
        <li>
          <a
            href={`/${data.locale}/news/${post.slug}/`}
            aria-current={data.post?.slug === post.slug ? "page" : undefined}
          >
            <time class="t-miniLabel muted" datetime={post.date}
              >{dateFormat.format(new Date(`${post.date}T00:00:00Z`))}</time
            >
            <span class="t-titleXS news-post-title">{post.title}</span>
          </a>
        </li>
      {/each}
    </ul>
  </nav>
{/snippet}

<a class="skip t-body" href="#main">{data.site.skip}</a>
<SiteHeader locale={data.locale} copy={data.site} />
<main id="main" class="news-page">
  <div class="container section-space news-inner">
    <header class="news-intro">
      {#if data.isArticle}<p class="t-display news-title">{copy.heading}</p>{:else}<h1
          class="t-display news-title"
        >
          {copy.heading}
        </h1>{/if}
      <p class="t-standfirstLarge muted">{copy.description}</p>
      <div class="news-links t-body">
        <a
          class="arrow-link arrow-link-label"
          href={`/${data.locale}/news/rss.xml`}
          data-sveltekit-reload
        >
          <span class="arrow-link-text">{copy.rss}</span><span
            class="arrow-link-icon"
            aria-hidden="true"><Icon name="functional/arrow/up_right" size={16} /></span
          >
        </a>
        <a class="arrow-link arrow-link-label" href="mailto:hello@eigin.ai">
          <span class="arrow-link-text">{copy.press}</span><span
            class="arrow-link-icon"
            aria-hidden="true"><Icon name="functional/arrow/up_right" size={16} /></span
          >
        </a>
      </div>
    </header>
    {#if data.post && data.Article}
      <div class="content-grid news-layout">
        <aside class="news-sidebar">{@render postList()}</aside>
        <details class="news-mobile-index">
          <summary class="t-miniLabel">{copy.posts}</summary>
          {@render postList()}
        </details>
        <article class="news-article">
          <header class="news-article-header">
            <time class="t-miniLabel muted" datetime={data.post.date}
              >{dateFormat.format(new Date(`${data.post.date}T00:00:00Z`))}</time
            >
            {#if data.isArticle}<h1 class="t-titleXl section-title news-article-title">
                {data.post.title}
              </h1>{:else}<h2 class="t-titleXl section-title news-article-title">
                <a href={`/${data.locale}/news/${data.post.slug}/`}>{data.post.title}</a>
              </h2>{/if}
          </header>
          <div class="news-prose t-body"><data.Article /></div>
        </article>
      </div>
    {:else}
      <p class="t-body muted news-empty">{copy.empty}</p>
    {/if}
  </div>
</main>
<SiteFooter locale={data.locale} copy={data.site} />
