<script lang="ts">
  import Preview from "#lib/Preview.svelte";
  import type { PageProps } from "./$types";
  let { data }: PageProps = $props();
</script>

<article class="guide-content">
  <div class="stack">
    <a href={`/review/calls/${data.call.slug}/selection`}>Recorded selection</a>
    <h2 class="t-titleM">
      {data.place === "selected" ? "Selected spec" : "Runner-up spec"}
    </h2>
    <p class="t-body">
      {data.awarded.author} · Revision {data.awarded.revisionId}
    </p>
    <a
      href={`/review/calls/${data.call.slug}/selection/${data.place}/download`}
      data-sveltekit-reload>Download recorded revision</a
    >
  </div>
  <div class="review-reading"><Preview text={data.awarded.markdown} /></div>
</article>
