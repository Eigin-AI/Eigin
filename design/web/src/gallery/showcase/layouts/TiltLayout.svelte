<script lang="ts">
  import type { Snippet } from "svelte";
  import Device3D from "@gallery/showcase/Device3D.svelte";
  import { headlineSide, type Shot, type Size } from "@gallery/showcase/shots";

  let { shot, size, moving, screen }: { shot: Shot; size: Size; moving: boolean; screen: Snippet } =
    $props();

  /* The phone takes the side the headline leaves free, or sits below it
     when the headline is centred or the canvas is tall. */
  const side = $derived(headlineSide(shot));
  const tall = $derived(size.width < size.height * 1.2);
  const below = $derived(Boolean(shot.headline) && (side === "center" || tall));
  const centerX = $derived(tall || side === "center" ? 0.5 : side === "left" ? 0.7 : 0.3);
  const centerY = $derived(below ? 0.6 : 0.5);
  const deviceHeight = $derived(
    size.height * (tall ? 0.68 : below ? 0.76 : 0.86) * shot.placement.scale,
  );

  /* Placement nudges the phone from where the layout puts it. */
  const offset = $derived(
    `${(size.width * shot.placement.x) / 100}px ${(size.height * shot.placement.y) / 100}px`,
  );
</script>

<!-- The phone angled in, clear of the headline. -->
<div
  class="device"
  style:left="{size.width * centerX}px"
  style:top="{size.height * centerY}px"
  style:translate={offset}
>
  <Device3D
    tilt={shot.tilt}
    scheme={shot.scheme}
    height={deviceHeight}
    glare={shot.glare}
    light={shot.light}
    {moving}
  >
    {@render screen()}
  </Device3D>
</div>

<style>
  .device {
    position: absolute;
    transform: translate(-50%, -50%);
  }
</style>
