<script lang="ts">
  import Preview from "#lib/Preview.svelte";
  import type { PageProps } from "./$types";
  let { data }: PageProps = $props();
</script>

<article aria-label="Selected submission">
  <div class="review-author">
    <div class="stack">
      <p class="t-miniLabel eyebrow">Submitted by</p>
      <h2 class="t-titleM">{data.selected.author}</h2>
      <p class="t-note">Revision {data.selected.revisionId}</p>
    </div>
    <a
      class="t-note"
      href="/review/calls/{data.call.slug}/submissions/{data.selected
        .id}/download"
      data-sveltekit-reload>Download Markdown</a
    >
  </div>
  <dl class="review-contact">
    <div>
      <dt class="t-miniLabel">Contact email</dt>
      <dd><a href="mailto:{data.selected.email}">{data.selected.email}</a></dd>
    </div>
    <div>
      <dt class="t-miniLabel">Git author email</dt>
      <dd>{data.selected.authorEmail}</dd>
    </div>
  </dl>
  <div class="review-reading"><Preview text={data.selected.markdown} /></div>
</article>
