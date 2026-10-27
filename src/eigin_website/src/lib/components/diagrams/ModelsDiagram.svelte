<script lang="ts">
  import { Icon } from "@eigin/ui";
  import type { DiagramLabels } from "../../content/trust/types";
  let { labels }: { labels: DiagramLabels["models"] } = $props();
</script>

<!-- Where your messages go: a local model inside your device, or, past your yes, Eigin Relay or your own provider. -->
<figure class="tschem" role="img" aria-label={labels.description}>
  <div class="tplate tplate--peach" data-color-scheme="light" aria-hidden="true">
    <svg viewBox="0 -9 540 340">
      <rect class="ts-wall" x="20" y="56" width="220" height="210" rx="14" />
      <text class="ts-name t-buttonSmall" x="36" y="84">{labels.device}</text>
      <path id="ts-mod-local" class="ts-line" d="M108 150 C130 150 130 180 130 206" />

      <rect class="ts-box" x="36" y="206" width="188" height="44" rx="14" />
      <text class="ts-name t-buttonSmall" x="130" y="233" text-anchor="middle">{labels.local}</text>
      <path class="ts-line" d="M108 150 H284" />
      <path id="ts-mod-relay" class="ts-line" d="M340 150 C361 150 361 100 370 100" />

      <rect class="ts-box" x="370" y="78" width="150" height="44" rx="14" />
      <text class="ts-name t-buttonSmall" x="445" y="105" text-anchor="middle">{labels.relay}</text>
      <path id="ts-mod-own" class="ts-line" d="M340 150 C361 150 361 200 370 200" />

      <rect class="ts-box" x="370" y="178" width="150" height="44" rx="14" />
      <text class="ts-name t-buttonSmall" x="445" y="205" text-anchor="middle">{labels.own}</text>
      <!-- One route at a time: local, then Eigin Relay, then your own provider. -->
      <path class="ts-pulse" d="M108 150 C130 150 130 180 130 206"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="13.50s"
          repeatCount="indefinite"
          values="38;38;-72;-72;38;38"
          keyTimes="0;0;0.0509;0.0806;0.1315;1"
          calcMode="linear"
        /></path
      >
      <path class="ts-pulse" d="M108 150 H340 C361 150 361 100 370 100"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="13.50s"
          repeatCount="indefinite"
          values="38;38;-148;-148;-300;-300;38;38"
          keyTimes="0;0.1509;0.237;0.3111;0.3815;0.4111;0.5676;1"
          calcMode="linear"
        /></path
      >
      <path class="ts-pulse" d="M108 150 H340 C361 150 361 200 370 200"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="13.50s"
          repeatCount="indefinite"
          values="38;38;-148;-148;-300;-300;38;38"
          keyTimes="0;0.5739;0.66;0.7341;0.8045;0.8341;0.9906;1"
          calcMode="linear"
        /></path
      >
      <rect class="ts-echo" x="278" y="138" width="68" height="24" rx="12" opacity="0">
        <animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="x"
          dur="13.50s"
          repeatCount="indefinite"
          values="278;278;278;266;278;278;278;266;266"
          keyTimes="0;0.2370;0.2410;0.3111;0.3151;0.6600;0.6640;0.7341;1"
          calcMode="linear"
        />
        <animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="y"
          dur="13.50s"
          repeatCount="indefinite"
          values="138;138;138;126;138;138;138;126;126"
          keyTimes="0;0.2370;0.2410;0.3111;0.3151;0.6600;0.6640;0.7341;1"
          calcMode="linear"
        />
        <animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="width"
          dur="13.50s"
          repeatCount="indefinite"
          values="68;68;68;92;68;68;68;92;92"
          keyTimes="0;0.2370;0.2410;0.3111;0.3151;0.6600;0.6640;0.7341;1"
          calcMode="linear"
        />
        <animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="height"
          dur="13.50s"
          repeatCount="indefinite"
          values="24;24;24;48;24;24;24;48;48"
          keyTimes="0;0.2370;0.2410;0.3111;0.3151;0.6600;0.6640;0.7341;1"
          calcMode="linear"
        />
        <animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="rx"
          dur="13.50s"
          repeatCount="indefinite"
          values="12;12;12;24;12;12;12;24;24"
          keyTimes="0;0.2370;0.2410;0.3111;0.3151;0.6600;0.6640;0.7341;1"
          calcMode="linear"
        />
        <animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="opacity"
          dur="13.50s"
          repeatCount="indefinite"
          values="0;0;0.6;0;0;0;0.6;0;0"
          keyTimes="0;0.2370;0.2410;0.3111;0.3151;0.6600;0.6640;0.7341;1"
          calcMode="linear"
        />
      </rect>
      <rect class="ts-gate" x="278" y="138" width="68" height="24" rx="12" />
      <text class="ts-gate-text t-buttonSmall" x="312" y="155" text-anchor="middle"
        >{labels.ask}</text
      >
    </svg>
    <span class="tschem-actor tschem-actor--logo" style="--x:14.8%;--y:46.8%;--w:11%"
      ><Icon name="brand/avatar" size="fill" /></span
    >
  </div>
</figure>
