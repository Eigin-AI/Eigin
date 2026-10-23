<script lang="ts">
  let { text }: { text: string } = $props();
</script>

<p class="detail-text t-body">{text}</p>

<style>
  .detail-text {
    margin: 0;
    padding: var(--spacing-n16) var(--spacing-n24);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    color: var(--color-text-standard-base);
  }
</style>
