<script lang="ts">
  import type { Snippet } from "svelte";
  import Device3D from "@gallery/showcase/Device3D.svelte";
  import { headlineSide, type Shot, type Size } from "@gallery/showcase/shots";

  let { shot, size, moving, screen }: { shot: Shot; size: Size; moving: boolean; screen: Snippet } =
    $props();

  /* The phone rises on the side the headline leaves free, or below it when
     the headline is centred over it. */
  const side = $derived(headlineSide(shot));
  const tall = $derived(size.width < size.height * 1.2);
  const below = $derived(Boolean(shot.headline) && (side === "center" || tall));
  const centerX = $derived(tall || side === "center" ? 0.5 : side === "left" ? 0.7 : 0.3);
  const deviceTop = $derived(size.height * (below ? 0.3 : 0.1));
  /* Tall enough to run off the bottom edge, so the phone rises into frame. */
  const deviceHeight = $derived(size.height * (tall ? 0.8 : 0.95) * shot.placement.scale);
  const facing = { yaw: 0, pitch: 0, roll: 0 };

  /* Placement nudges the phone from where the layout puts it. */
  const offset = $derived(
    `${(size.width * shot.placement.x) / 100}px ${(size.height * shot.placement.y) / 100}px`,
  );
</script>

<!-- A front-facing phone rising from the bottom edge. -->
<div
  class="device"
  style:left="{size.width * centerX}px"
  style:top="{deviceTop}px"
  style:translate={offset}
>
  <Device3D
    tilt={facing}
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
    transform: translateX(-50%);
  }
</style>
