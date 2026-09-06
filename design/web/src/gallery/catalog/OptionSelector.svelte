<script lang="ts">
  import { SegmentedControl } from "@lib";

  let {
    options,
    value = $bindable(),
  }: {
    options: readonly string[];
    value: string;
  } = $props();

  const segments = $derived(options.map((option) => ({ value: option, label: option })));
</script>

<!-- Specimen controls, built from the design system's own SegmentedControl. -->
<div class="picker">
  <SegmentedControl {segments} selection={value} onSelect={(next) => (value = next)} />
</div>

<style>
  /* Segments stretch to fill their track, so size the track to its content. */
  .picker {
    width: max-content;
    max-width: 100%;
  }
</style>
