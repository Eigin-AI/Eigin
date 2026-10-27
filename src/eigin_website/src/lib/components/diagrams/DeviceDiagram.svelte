<script lang="ts">
  import { Icon } from "@eigin/ui";
  import type { DiagramLabels } from "../../content/trust/types";
  let { labels }: { labels: DiagramLabels["device"] } = $props();
</script>

<figure class="tschem" role="img" aria-label={labels.description}>
  <div class="tplate tplate--olive" data-color-scheme="light" aria-hidden="true">
    <svg viewBox="0 -20 540 340">
      <rect class="ts-wall" x="20" y="40" width="340" height="222" rx="14" />
      <text class="ts-name t-buttonSmall" x="36" y="68">{labels.device}</text>
      <g class="ts-cycle-on"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="opacity"
          dur="16.32s"
          repeatCount="indefinite"
          values="1;1;0;0;1"
          keyTimes="0;0.672;0.703;0.969;1"
          calcMode="spline"
          keySplines="0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1"
        />
        <path
          transform="translate(322 52)"
          fill="none"
          stroke="currentColor"
          stroke-linecap="round"
          stroke-width="3"
          d="M12 18h.01m-2.839-2.828A4 4 0 0 1 12 14c1.104 0 2.104.448 2.828 1.172m-8.485-2.829A7.98 7.98 0 0 1 12 10c2.209 0 4.209.895 5.657 2.343M3.515 9.515A11.96 11.96 0 0 1 12 6c3.314 0 6.314 1.343 8.485 3.515"
        />
      </g>
      <g class="ts-cycle-off" opacity="0"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="opacity"
          dur="16.32s"
          repeatCount="indefinite"
          values="0;0;1;1;0"
          keyTimes="0;0.672;0.703;0.969;1"
          calcMode="spline"
          keySplines="0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1"
        />
        <path
          class="ts-solid"
          transform="translate(322 52)"
          d="M19.71 2.838c.733.147 1.306.72 1.453 1.453a3.560 3.560 0 0 1-.773 2.995l-2.751 3.252l1.944 7.131a1.250 1.250 0 0 1-.322 1.213l-1.302 1.302a1.010 1.010 0 0 1-1.597-.224l-2.993-5.387l-3.258 2.255v.787c0 .332-.132.650-.366.884l-1.683 1.683a1.010 1.010 0 0 1-1.673-.395l-.544-1.631l-1.631-.544a1.010 1.010 0 0 1-.395-1.673l1.683-1.683a1.250 1.250 0 0 1 .884-.366h.787l2.255-3.258L4.041 7.640a1.010 1.010 0 0 1-.224-1.597L5.119 4.740a1.250 1.250 0 0 1 1.213-.322l7.130 1.944l3.253-2.752a3.560 3.560 0 0 1 2.995-.772"
        />
      </g>
      <path class="ts-line" d="M181 168 C158 168 158 105 132 105" />
      <rect class="ts-box" x="36" y="90" width="96" height="30" rx="14" />
      <text class="ts-label t-body" x="84" y="110" text-anchor="middle">{labels.memory}</text>
      <path class="ts-line" d="M181 168 C158 168 158 147 132 147" />
      <rect class="ts-box" x="36" y="132" width="96" height="30" rx="14" />
      <text class="ts-label t-body" x="84" y="152" text-anchor="middle">{labels.goals}</text>
      <path class="ts-line" d="M181 168 C158 168 158 189 132 189" />
      <rect class="ts-box" x="36" y="174" width="96" height="30" rx="14" />
      <text class="ts-label t-body" x="84" y="194" text-anchor="middle">{labels.voice}</text>
      <path class="ts-line" d="M181 168 C158 168 158 231 132 231" />
      <rect class="ts-box" x="36" y="216" width="96" height="30" rx="14" />
      <text class="ts-label t-body" x="84" y="236" text-anchor="middle">{labels.notes}</text>
      <path class="ts-line" d="M229 168 H263" />
      <text class="ts-label t-body" x="290" y="218" text-anchor="middle">{labels.conversation}</text
      >
      <g class="ts-cycle-off" opacity="0"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="opacity"
          dur="16.32s"
          repeatCount="indefinite"
          values="0;0;1;1;0"
          keyTimes="0;0.672;0.703;0.969;1"
          calcMode="spline"
          keySplines="0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1"
        />
        <path class="ts-line" d="M290 130 V145" />

        <rect class="ts-box" x="230" y="86" width="120" height="44" rx="14" />
        <text class="ts-name t-buttonSmall" x="290" y="113" text-anchor="middle"
          >{labels.local}</text
        >
      </g>
      <g class="ts-cycle-net"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="opacity"
          dur="16.32s"
          repeatCount="indefinite"
          values="1;1;0.12;0.12;1"
          keyTimes="0;0.672;0.703;0.969;1"
          calcMode="spline"
          keySplines="0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1;0.42 0 0.58 1"
        />
        <path class="ts-line" d="M315 168 H390" />

        <rect class="ts-box" x="390" y="146" width="130" height="44" rx="14" />
        <text class="ts-name t-buttonSmall" x="455" y="173" text-anchor="middle"
          >{labels.cloud}</text
        >
      </g>
      <!-- Shares one clock with the online/offline switch above, so they never drift apart. -->
      <!-- The agent pulls from what it knows, then sends the conversation out: twice online, once offline. -->
      <path class="ts-pulse" d="M181 168 C158 168 158 105 132 105"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="16.32s"
          repeatCount="indefinite"
          values="38;-91;-91;38;38"
          keyTimes="0;0.0494;0.0648;0.1142;1"
          calcMode="linear"
        /></path
      >
      <path class="ts-pulse" d="M181 168 C158 168 158 231 132 231"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="16.32s"
          repeatCount="indefinite"
          values="38;38;-91;-91;38;38"
          keyTimes="0;0.3361;0.3855;0.4009;0.4503;1"
          calcMode="linear"
        /></path
      >
      <path class="ts-pulse" d="M181 168 C158 168 158 147 132 147"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="16.32s"
          repeatCount="indefinite"
          values="38;38;-61;-61;38;38"
          keyTimes="0;0.7029;0.7408;0.7562;0.7941;1"
          calcMode="linear"
        /></path
      >
      <path class="ts-pulse" d="M229 168 H390"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="16.32s"
          repeatCount="indefinite"
          values="38;38;-167;-167;38;38;-167;-167;38;38"
          keyTimes="0;0.1210;0.1995;0.2240;0.3025;0.4571;0.5356;0.5601;0.6386;1"
          calcMode="linear"
        /></path
      >
      <path class="ts-pulse" d="M229 168 H290 V130"
        ><animate
          begin="indefinite"
          data-motion-delay="0"
          attributeName="stroke-dashoffset"
          dur="16.32s"
          repeatCount="indefinite"
          values="38;38;-105;-105;38;38"
          keyTimes="0;0.8002;0.8550;0.8795;0.9343;1"
          calcMode="linear"
        /></path
      >
      <!-- A backing disc, so lines and pulses never show through the conversation icon's cut-outs. -->
      <circle class="ts-on-solid" cx="290" cy="168" r="22" />
    </svg>
    <span class="tschem-actor tschem-actor--logo" style="--x:38%;--y:55.3%;--w:9%"
      ><Icon name="brand/avatar" size="fill" /></span
    >
    <span class="tschem-actor" style="--x:53.7%;--y:55.3%;--w:9%"
      ><Icon name="brand/chat_fill" size="fill" /></span
    >
  </div>
</figure>
