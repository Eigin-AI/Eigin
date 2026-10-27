<script lang="ts">
  let { label, compact = false }: { label: string; compact?: boolean } = $props();
</script>

<div class="visual-placeholder" class:compact aria-hidden="true">
  <span class="placeholder-line"></span>
  <span class="t-miniLabel">{label}</span>
  <span class="placeholder-line"></span>
</div>
