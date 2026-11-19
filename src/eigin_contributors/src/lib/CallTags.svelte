<script lang="ts">
  let { status }: { status?: string } = $props();
</script>

<div class="call-tags">
  <span class="call-tag t-tag">Request for spec</span>
  {#if status}<span class="call-status t-miniLabel">{status}</span>{/if}
</div>
