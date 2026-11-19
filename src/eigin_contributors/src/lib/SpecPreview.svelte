<script lang="ts">
  import Preview from "./Preview.svelte";
  let { markdown }: { markdown: string } = $props();
</script>

<aside class="spec-preview">
  <div class="preview-heading">
    <h2 class="t-titleS">Spec preview</h2>
    <span class="t-note">As the review team will see it</span>
  </div>
  {#if markdown}
    <!-- Scrollable preview must be keyboard-accessible. -->
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <div
      class="preview-scroll"
      role="region"
      aria-label="Markdown preview"
      tabindex="0"
    >
      <Preview text={markdown} />
    </div>
  {:else}<div class="preview-empty">
      <p class="t-standfirst">Your thinking goes here.</p>
      <p class="t-body">
        Choose a Markdown file to preview the headings, text, and code before
        submitting.
      </p>
    </div>{/if}
</aside>
