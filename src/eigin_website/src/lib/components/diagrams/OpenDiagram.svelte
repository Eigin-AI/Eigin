<script lang="ts">
  import type { DiagramLabels } from "../../content/trust/types";
  let { labels }: { labels: DiagramLabels["open"] } = $props();
</script>

<figure class="tschem" role="img" aria-label={labels.description}>
  <div class="tplate tplate--peach" data-color-scheme="light" aria-hidden="true">
    <svg viewBox="0 -4 540 340">
      <rect class="ts-solid" x="20" y="56" width="230" height="220" rx="14" />
      <text class="ts-name ts-on-solid t-buttonSmall" x="36" y="84">{labels.others}</text>
      <text class="ts-on-solid ts-big t-display" x="135" y="187" text-anchor="middle">?</text>
      <text class="ts-on-solid ts-label ts-label--xs t-body" x="135" y="250" text-anchor="middle"
        >{labels.trustUs}</text
      >
      <text class="ts-name t-buttonSmall" x="306" y="84">{labels.eigin}</text>
      <rect class="ts-wall" x="290" y="56" width="230" height="220" rx="14" />
      <rect class="ts-box" x="306" y="96" width="198" height="28" rx="14" />
      <text class="ts-label ts-label--sm t-body" x="318" y="115">{labels.items[0]}</text>
      <rect class="ts-box" x="306" y="130" width="198" height="28" rx="14" />
      <text class="ts-label ts-label--sm t-body" x="318" y="149">{labels.items[1]}</text>
      <rect class="ts-box" x="306" y="164" width="198" height="28" rx="14" />
      <text class="ts-label ts-label--sm t-body" x="318" y="183">{labels.items[2]}</text>
      <rect class="ts-box" x="306" y="198" width="198" height="28" rx="14" />
      <text class="ts-label ts-label--sm t-body" x="318" y="217">{labels.items[3]}</text>
      <rect class="ts-box" x="306" y="232" width="198" height="28" rx="14" />
      <text class="ts-label ts-label--sm t-body" x="318" y="251">{labels.items[4]}</text>
      <g class="ts-lens"
        ><circle class="ts-lens-glass" cx="478" cy="110" r="20" /><path
          class="ts-line"
          d="M492 124 l14 14"
        /></g
      >
    </svg>
  </div>
</figure>
