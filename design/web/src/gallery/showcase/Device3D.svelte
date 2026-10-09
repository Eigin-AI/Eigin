<script lang="ts">
  import type { Snippet } from "svelte";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";
  import { devices } from "@gallery/frames/devices";
  import { glareFor } from "./glare";
  import type { Light, Tilt } from "./shots";

  let {
    tilt,
    scheme,
    height,
    moving = false,
    glare = 0.15,
    light = { angle: -40, height: 35 },
    children,
  }: {
    tilt: Tilt;
    scheme: "light" | "dark";
    /** Outside height of the phone, in canvas pixels. */
    height: number;
    /** Plays the idle float. Stills sample it at a chosen time instead. */
    moving?: boolean;
    /** Studio light on the glass, from 0 (none) to 1. */
    glare?: number;
    /** Where the softbox hangs. */
    light?: Light;
    children: Snippet;
  } = $props();

  const configuration = devices[0].configurations[0];
  /* Screen, then the 12px bezel and 3px rim on each side. */
  const naturalHeight = configuration.height + 30;
  const zoom = $derived(height / naturalHeight);

  /* Matches .device-3d's perspective, in the phone's own pixels. */
  const perspective = 2600;
  const reflection = $derived(glareFor(tilt, light, configuration, perspective));
  /* Light glass hides a reflection that dark glass shows, so the same
     setting reads the same on both. */
  const strength = $derived(glare * reflection.strength * (scheme === "light" ? 2 : 1));
  /* Far-off reflections only reach the glass at their soft edge. */
  const clamp = (value: number) => Math.max(-80, Math.min(180, value));

  /* Stacked silhouettes behind the face fake the phone's thickness. */
  const slices = Array.from({ length: 12 }, (_, index) => index + 1);
</script>

<!-- Zoom rather than scale, so text lays out at the final size and stays sharp. -->
<div
  class="device-3d"
  style:zoom
  style:--yaw="{tilt.yaw}deg"
  style:--pitch="{tilt.pitch}deg"
  style:--roll="{tilt.roll}deg"
  style:--glare={strength}
  style:--glare-x="{clamp(reflection.x)}%"
  style:--glare-y="{clamp(reflection.y)}%"
>
  <div class="body" class:moving>
    <div class="shadow far"></div>
    <div class="shadow near"></div>
    {#each slices as depth (depth)}
      <div class="slice" style:--depth={depth}></div>
    {/each}
    <div class="face">
      <DeviceFrame
        fit={false}
        colorScheme={scheme}
        width={configuration.width}
        height={configuration.height}
        safeAreaTop={configuration.safeAreaTop}
        safeAreaBottom={configuration.safeAreaBottom}
      >
        {@render children()}
      </DeviceFrame>
      <div class="sheen"></div>
    </div>
  </div>
</div>

<style>
  .device-3d {
    perspective: 2600px;
    flex: none;
  }

  .body {
    position: relative;
    transform-style: preserve-3d;
    transform: rotateX(var(--pitch)) rotateY(var(--yaw)) rotateZ(var(--roll));
  }

  .body.moving {
    animation: float 9s ease-in-out infinite;
  }

  /* Starts and ends on the resting pose, so time 0 is the still. */
  @keyframes float {
    0%,
    100% {
      transform: rotateX(var(--pitch)) rotateY(var(--yaw)) rotateZ(var(--roll));
    }
    50% {
      transform: rotateX(calc(var(--pitch) - 3deg)) rotateY(calc(var(--yaw) + 7deg))
        rotateZ(var(--roll)) translateY(-16px);
    }
  }

  /* Titanium rim around the bezel. */
  .face {
    position: relative;
    padding: 3px;
    border-radius: 57px;
    background: linear-gradient(
      135deg,
      #a4a7ab 0%,
      #4a4c50 30%,
      #2b2c2e 55%,
      #6d7074 80%,
      #b5b8bc 100%
    );
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.25);
  }

  .slice,
  .shadow {
    position: absolute;
    inset: 0;
    border-radius: 57px;
  }

  .slice {
    background: color-mix(in srgb, #55585c, #0c0c0d calc(var(--depth) * 7%));
    transform: translateZ(calc(var(--depth) * -2px));
  }

  /* Light from the upper left: the shadow falls down and to the right. */
  .shadow.far {
    background: rgb(0 0 0 / 0.2);
    transform: translateZ(-200px) translate(50px, 70px);
    filter: blur(80px);
  }

  .shadow.near {
    background: rgb(0 0 0 / 0.18);
    transform: translateZ(-30px) translate(10px, 14px);
    filter: blur(22px);
  }

  /* The softbox's reflection: a broad bloom centred where the glass mirrors
     it into the camera, so it slides as the phone turns, and the rest of the
     glass a touch darker for the dim studio it reflects. */
  .sheen {
    position: absolute;
    inset: 15px;
    border-radius: 42px;
    background:
      radial-gradient(
        ellipse 110% 80% at var(--glare-x) var(--glare-y),
        rgb(255 255 255 / calc(var(--glare) * 0.95)) 0%,
        rgb(255 255 255 / calc(var(--glare) * 0.6)) 28%,
        rgb(255 255 255 / calc(var(--glare) * 0.12)) 46%,
        rgb(255 255 255 / 0) 62%
      ),
      radial-gradient(
        ellipse 170% 130% at var(--glare-x) var(--glare-y),
        rgb(0 0 0 / 0) 30%,
        rgb(0 0 0 / calc(var(--glare) * 0.22)) 100%
      );
    transform: translateZ(1px);
    pointer-events: none;
  }
</style>
