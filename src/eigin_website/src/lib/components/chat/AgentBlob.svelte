<script lang="ts">
  import { untrack } from "svelte";
  import { MorphBlob, MorphIntensity } from "@eigin/ui";

  /** The shared agent blob, without app chrome or a brand mark. */
  let { active = true }: { active?: boolean } = $props();
  let intensity = $state(MorphIntensity.none);
  $effect(() => {
    const engaged = active;
    intensity = untrack(() => intensity.transitionedTo(engaged, performance.now() / 1000));
  });
</script>

<div class="agent">
  <MorphBlob
    {intensity}
    breath={intensity}
    tempo={0.55}
    breathPulse={0.025}
    color="var(--color-surface-impact-base)"
  />
</div>
