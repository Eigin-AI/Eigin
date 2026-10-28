<script lang="ts">
  import { untrack } from "svelte";
  import { MorphBlob, MorphIntensity } from "@eigin/ui";

  /** An agent that eases into a wobble while sharing or receiving knowledge. */
  let { engaged, seed }: { engaged: boolean; seed: number } = $props();
  let intensity = $state(MorphIntensity.none);

  $effect(() => {
    const moving = engaged;
    intensity = untrack(() =>
      intensity.transitionedTo(moving, performance.now() / 1000, moving ? 0.28 : 0.42),
    );
  });
</script>

<MorphBlob
  shownAt={-100 - seed * 7}
  {intensity}
  intensityScale={0.45}
  tempo={0.8}
  color="var(--color-icon-standard-base)"
/>
