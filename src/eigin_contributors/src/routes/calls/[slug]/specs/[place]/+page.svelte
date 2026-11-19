<script lang="ts">
  import { marked } from "marked";
  import Preview from "#lib/Preview.svelte";
  import type { PageProps } from "./$types";
  let { data }: PageProps = $props();
  const hasTitle = $derived(
    marked
      .lexer(data.spec.markdown.slice(0, 2048))
      .some((token) => token.type === "heading" && token.depth === 1),
  );
</script>

<svelte:head
  ><title>{data.spec.title} · {data.spec.author} · Eigin contributors</title
  ></svelte:head
>
<section class="container section">
  <a class="t-body" href={`/calls/${data.callSlug}`}>Back to the call</a>
  <div class="published-spec-layout spaced">
    <aside class="published-credit">
      <p class="t-miniLabel eyebrow">A specification by</p>
      <h2 class="t-titleM">{data.spec.author}</h2>
    </aside>
    <article class="published-reading" aria-label="Published specification">
      {#if !hasTitle}<h1 class="t-titleL">{data.spec.title}</h1>{/if}
      <Preview text={data.spec.markdown} />
    </article>
  </div>
</section>
