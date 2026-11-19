<script lang="ts">
  import FoldoutGuide from "./FoldoutGuide.svelte";
  let { text }: { text: string } = $props();
</script>

<FoldoutGuide {text} class="call-constraints trust-items" />
