<script lang="ts">
  let { id }: { id: string } = $props();
</script>

<div class="placeholder">
  <p class="t-titleS">{id}</p>
  <p class="t-note">Screen skeleton — components land here as they're ported.</p>
</div>

<style>
  .placeholder {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-n8);
    text-align: center;
    padding: var(--spacing-n24);
  }
</style>
