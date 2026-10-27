<script lang="ts">
  import { Icon } from "@eigin/ui";
  import type { DiagramLabels } from "../../content/trust/types";
  let { labels }: { labels: DiagramLabels["money"] } = $props();
</script>

<figure class="tschem" role="img" aria-label={labels.description}>
  <div class="tplate tplate--dark" data-color-scheme="dark" aria-hidden="true">
    <svg viewBox="0 -4 540 340">
      <rect class="ts-wall" x="20" y="56" width="200" height="220" rx="14" />
      <text class="ts-name t-buttonSmall" x="36" y="84">Eigin</text>
      <path class="ts-line" d="M300 84 C262 84 258 148 220 148" />

      <rect class="ts-box" x="300" y="56" width="220" height="56" rx="14" />
      <text class="ts-name t-buttonSmall" x="410" y="80" text-anchor="middle">{labels.cloud}</text>
      <text class="ts-label t-body" x="410" y="100" text-anchor="middle">{labels.cloudNote}</text>
      <path class="ts-line" d="M300 152 C262 152 258 166 220 166" />

      <rect class="ts-box" x="300" y="124" width="220" height="56" rx="14" />
      <text class="ts-name t-buttonSmall" x="410" y="148" text-anchor="middle">{labels.team}</text>
      <text class="ts-label t-body" x="410" y="168" text-anchor="middle">{labels.teamNote}</text>
      <path class="ts-x" d="M306 207 l10 10 m0 -10 l-10 10" />
      <text class="ts-label ts-struck t-body" x="328" y="218">{labels.refused[0]}</text>
      <path class="ts-x" d="M306 235 l10 10 m0 -10 l-10 10" />
      <text class="ts-label ts-struck t-body" x="328" y="246">{labels.refused[1]}</text>
      <path class="ts-x" d="M306 263 l10 10 m0 -10 l-10 10" />
      <text class="ts-label ts-struck t-body" x="328" y="274">{labels.refused[2]}</text>
      <path class="ts-pulse" d="M300 152 C262 152 258 166 220 166"
        ><animate
          begin="indefinite"
          data-motion-delay="0.59"
          attributeName="stroke-dashoffset"
          dur="1.29s"
          repeatCount="indefinite"
          values="38;-88;-88"
          keyTimes="0;0.6117;1"
          calcMode="linear"
        /></path
      >
      <path class="ts-pulse" d="M300 84 C262 84 258 148 220 148"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="1.44s"
          repeatCount="indefinite"
          values="38;-113;-113"
          keyTimes="0;0.6537;1"
          calcMode="linear"
        /></path
      >
    </svg>
    <span
      class="tschem-actor tschem-actor--logo"
      style="--x:22.2%;--y:52.9%;--w:13%;--actor:var(--color-surface-impact-base)"
      ><Icon name="brand/avatar" size="fill" /></span
    >
  </div>
</figure>
