<script lang="ts">
  import { Icon } from "@eigin/ui";
  import type { DiagramLabels } from "../../content/trust/types";
  let { labels }: { labels: DiagramLabels["sync"] } = $props();
</script>

<figure class="tschem" role="img" aria-label={labels.description}>
  <div class="tplate tplate--peach" data-color-scheme="light" aria-hidden="true">
    <svg viewBox="0 -12 540 340">
      <path class="ts-line" d="M150 164 H390" />
      <path class="ts-pulse" d="M150 164 H390"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="4.75s"
          repeatCount="indefinite"
          values="38;-246;-246;38;38"
          keyTimes="0;0.3737;0.5000;0.8737;1"
          calcMode="linear"
        /></path
      >
      <rect class="ts-box" x="20" y="64" width="130" height="188" rx="14" />
      <text class="ts-name t-buttonSmall" x="85" y="92" text-anchor="middle">{labels.device}</text>
      <rect class="ts-bubble" x="32" y="108" width="106" height="58" rx="14" />
      <text class="ts-label ts-label--sm ts-on-bubble t-body" x="85" y="132" text-anchor="middle"
        >{labels.message[0]}</text
      >
      <text class="ts-label ts-label--sm ts-on-bubble t-body" x="85" y="152" text-anchor="middle"
        >{labels.message[1]}</text
      >
      <path
        class="ts-key"
        d="M68 214 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0 M84 214 h18 m-6 0 v7 m-6 -7 v6"
      />
      <rect class="ts-box" x="390" y="64" width="130" height="188" rx="14" />
      <text class="ts-name t-buttonSmall" x="455" y="92" text-anchor="middle">{labels.team}</text>
      <rect class="ts-bubble" x="402" y="108" width="106" height="58" rx="14" />
      <text class="ts-label ts-label--sm ts-on-bubble t-body" x="455" y="132" text-anchor="middle"
        >{labels.message[0]}</text
      >
      <text class="ts-label ts-label--sm ts-on-bubble t-body" x="455" y="152" text-anchor="middle"
        >{labels.message[1]}</text
      >
      <path
        class="ts-key"
        d="M438 214 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0 M454 214 h18 m-6 0 v7 m-6 -7 v6"
      />
      <rect class="ts-box" x="235" y="129" width="70" height="70" rx="14" />
      <text class="ts-name t-buttonSmall" x="270" y="226" text-anchor="middle">{labels.relay}</text>
      <text class="ts-label ts-label--xs t-body" x="270" y="246" text-anchor="middle"
        >{labels.relayNote}</text
      >
    </svg>
    <span class="tschem-actor tschem-actor--logo" style="--x:50%;--y:51.8%;--w:6.5%"
      ><Icon name="brand/avatar" size="fill" /></span
    >
  </div>
</figure>
