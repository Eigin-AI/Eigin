<script lang="ts">
  import SweepRing from "./SweepRing.svelte";
  import "./screen-state.css";

  let { title }: { title: string } = $props();
</script>

<!-- Indeterminate full-area loading: an indicator and one line of context. -->
<div class="eigin-screen-state" role="status">
  <SweepRing size={48} stroke={3} />
  <h2 class="t-titleS">{title}</h2>
</div>
