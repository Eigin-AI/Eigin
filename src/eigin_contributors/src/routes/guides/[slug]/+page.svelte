<script lang="ts">
  import FoldoutGuide from "#lib/FoldoutGuide.svelte";
  let { data } = $props();
</script>

<svelte:head><title>{data.title} · Eigin</title></svelte:head>
<section class="container section">
  <div class="page-intro">
    <h1 class="t-display page-title">{data.title}</h1>
  </div>
  <article class="guide-content spaced">
    <FoldoutGuide text={data.body} />
  </article>
</section>
