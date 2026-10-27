<script lang="ts">
  import { Icon } from "@eigin/ui";
  import type { DiagramLabels } from "../../content/trust/types";
  let { labels }: { labels: DiagramLabels["actions"] } = $props();
</script>

<figure class="tschem" role="img" aria-label={labels.description}>
  <div class="tswap">
    <div class="tplate tplate--dark" data-color-scheme="dark" aria-hidden="true">
      <svg viewBox="0 -18 540 340">
        <defs>
          <symbol id="ts-padlock" viewBox="0 0 28 28">
            <circle cx="14" cy="14" r="14" fill="var(--color-surface-standard-elevated)" />
            <path
              d="M10 13 V10.5 a4 4 0 0 1 8 0 V13"
              fill="none"
              stroke="var(--color-text-standard-base)"
              stroke-width="2.4"
              stroke-linecap="round"
            />
            <rect
              x="8"
              y="12.5"
              width="12"
              height="9"
              rx="2"
              fill="var(--color-text-standard-base)"
            />
          </symbol>
        </defs>
        <path
          class="ts-wall"
          d="M446 151 V36 A14 14 0 0 0 432 22 H42 A14 14 0 0 0 28 36 V268 A14 14 0 0 0 42 282 H432 A14 14 0 0 0 446 268 V183"
        />
        <path class="ts-wall" d="M28 52 H446" />
        <circle class="ts-solid" cx="46" cy="37" r="4" /><circle
          class="ts-solid"
          cx="60"
          cy="37"
          r="4"
        /><circle class="ts-solid" cx="74" cy="37" r="4" />
        <text class="ts-name t-buttonSmall" x="237" y="42" text-anchor="middle"
          >{labels.others}</text
        >
        <path class="ts-wall" d="M446 151 L438 159 M446 183 L438 175" />
        <path
          class="ts-grow ts-web"
          style="--l:1;stroke-width:1.5"
          pathLength="1"
          d="M233.0 167.0 L198.7 171.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M198.7 171.5 L167.0 194.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M167.0 194.4 L136.6 225.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M136.6 225.5 L113.7 251.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M113.7 251.3 L74.4 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M136.6 225.5 L82.6 247.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M82.6 247.0 L34.3 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M167.0 194.4 L121.5 198.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M121.5 198.6 L77.3 216.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M77.3 216.9 L34.0 238.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M77.3 216.9 L34.0 214.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M198.7 171.5 L157.9 161.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M157.9 161.5 L120.1 171.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M120.1 171.9 L70.9 179.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M70.9 179.3 L34.0 198.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M70.9 179.3 L34.0 173.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M157.9 161.5 L125.6 146.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M125.6 146.9 L71.1 150.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M71.1 150.0 L34.0 145.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M125.6 146.9 L90.2 127.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M90.2 127.4 L34.0 119.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M90.2 127.4 L34.0 101.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:1;stroke-width:1.5"
          pathLength="1"
          d="M233.0 167.0 L213.5 148.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M213.5 148.5 L171.2 130.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M171.2 130.4 L118.2 122.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M118.2 122.8 L84.2 125.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M84.2 125.6 L34.0 119.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M84.2 125.6 L34.0 107.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M118.2 122.8 L84.2 98.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M84.2 98.5 L34.0 84.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M171.2 130.4 L162.1 107.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M162.1 107.2 L102.5 81.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M102.5 81.8 L62.7 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M162.1 107.2 L158.0 88.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M158.0 88.6 L123.2 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M213.5 148.5 L210.2 130.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M210.2 130.7 L181.1 107.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M181.1 107.9 L149.4 83.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M149.4 83.7 L106.0 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M149.4 83.7 L130.7 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M181.1 107.9 L167.4 78.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M167.4 78.5 L139.4 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M167.4 78.5 L166.5 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M210.2 130.7 L205.6 106.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M205.6 106.2 L191.7 81.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M191.7 81.0 L185.4 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:1;stroke-width:1.5"
          pathLength="1"
          d="M233.0 167.0 L235.8 147.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M235.8 147.9 L228.3 126.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M228.3 126.5 L217.7 108.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M217.7 108.7 L213.3 78.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M213.3 78.1 L204.5 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M228.3 126.5 L233.8 104.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M233.8 104.1 L228.1 87.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M228.1 87.1 L220.6 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M228.1 87.1 L230.6 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M233.8 104.1 L242.2 84.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M242.2 84.6 L244.8 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M235.8 147.9 L248.0 130.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M248.0 130.6 L248.3 103.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M248.3 103.5 L247.4 81.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M247.4 81.5 L253.5 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M248.3 103.5 L258.9 89.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M258.9 89.4 L271.3 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M248.0 130.6 L268.1 103.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M268.1 103.3 L265.6 87.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M265.6 87.4 L276.1 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M265.6 87.4 L285.0 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M268.1 103.3 L292.9 79.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M292.9 79.0 L302.5 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M292.9 79.0 L314.5 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:1;stroke-width:1.5"
          pathLength="1"
          d="M233.0 167.0 L261.8 147.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M261.8 147.6 L270.8 127.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M270.8 127.7 L274.7 107.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M274.7 107.7 L278.1 87.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M278.1 87.9 L299.9 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M274.7 107.7 L310.1 79.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M310.1 79.2 L319.9 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M310.1 79.2 L344.1 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M270.8 127.7 L304.5 110.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M304.5 110.0 L313.8 86.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M313.8 86.6 L333.9 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M313.8 86.6 L347.2 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M304.5 110.0 L361.8 81.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M361.8 81.6 L382.5 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M361.8 81.6 L403.4 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M261.8 147.6 L302.4 140.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M302.4 140.2 L340.6 105.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M340.6 105.0 L351.9 81.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M351.9 81.6 L366.5 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M351.9 81.6 L389.1 58.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M340.6 105.0 L389.5 93.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M389.5 93.4 L440.0 60.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M302.4 140.2 L347.1 141.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M347.1 141.6 L384.6 114.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M384.6 114.0 L440.0 80.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M384.6 114.0 L440.0 112.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M347.1 141.6 L386.2 148.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M386.2 148.6 L440.0 142.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:1;stroke-width:1.5"
          pathLength="1"
          d="M233.0 167.0 L266.2 178.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M266.2 178.3 L307.9 173.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M307.9 173.7 L343.7 164.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M343.7 164.2 L380.7 154.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M380.7 154.1 L440.0 147.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M343.7 164.2 L397.3 179.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M397.3 179.4 L440.0 167.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M397.3 179.4 L440.0 201.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M307.9 173.7 L350.7 195.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M350.7 195.1 L380.0 192.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M380.0 192.3 L440.0 198.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M380.0 192.3 L440.0 215.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M350.7 195.1 L390.3 214.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M390.3 214.4 L440.0 224.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M266.2 178.3 L302.7 207.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M302.7 207.5 L354.8 214.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M354.8 214.0 L397.8 211.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M397.8 211.8 L440.0 206.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M397.8 211.8 L440.0 230.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M354.8 214.0 L394.3 238.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M394.3 238.1 L440.0 244.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M394.3 238.1 L440.0 273.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M302.7 207.5 L311.6 226.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M311.6 226.6 L372.7 255.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M372.7 255.3 L416.1 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M311.6 226.6 L326.3 247.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M326.3 247.2 L373.2 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M326.3 247.2 L356.0 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:1;stroke-width:1.5"
          pathLength="1"
          d="M233.0 167.0 L239.4 186.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M239.4 186.3 L255.2 205.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M255.2 205.1 L277.8 225.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M277.8 225.8 L291.0 247.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M291.0 247.9 L308.0 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M255.2 205.1 L255.8 227.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M255.8 227.9 L266.3 246.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M266.3 246.2 L281.9 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M239.4 186.3 L235.4 208.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M235.4 208.2 L243.2 229.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M243.2 229.8 L251.6 251.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M251.6 251.3 L258.3 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M243.2 229.8 L239.1 246.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M239.1 246.6 L241.1 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M235.4 208.2 L227.0 230.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M227.0 230.0 L232.3 247.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M232.3 247.7 L236.4 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M232.3 247.7 L227.4 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M227.0 230.0 L218.4 250.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M218.4 250.3 L223.8 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M218.4 250.3 L211.3 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:1;stroke-width:1.5"
          pathLength="1"
          d="M233.0 167.0 L221.6 185.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M221.6 185.0 L220.6 207.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M220.6 207.7 L222.0 227.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M222.0 227.8 L226.5 245.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M226.5 245.1 L225.2 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M222.0 227.8 L212.7 249.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M212.7 249.2 L203.0 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M220.6 207.7 L204.2 223.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M204.2 223.4 L197.1 251.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M197.1 251.5 L185.7 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M204.2 223.4 L178.2 253.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M178.2 253.7 L164.6 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2;stroke-width:1.5"
          pathLength="1"
          d="M221.6 185.0 L193.3 206.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M193.3 206.7 L183.0 230.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M183.0 230.0 L180.9 251.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M180.9 251.3 L159.7 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M183.0 230.0 L146.3 255.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M146.3 255.2 L141.7 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M146.3 255.2 L121.3 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3;stroke-width:1.2"
          pathLength="1"
          d="M193.3 206.7 L156.8 224.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M156.8 224.3 L150.4 246.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M150.4 246.9 L132.2 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M150.4 246.9 L111.3 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4;stroke-width:1.2"
          pathLength="1"
          d="M156.8 224.3 L106.0 247.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M106.0 247.9 L72.7 276.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:5;stroke-width:1.2"
          pathLength="1"
          d="M106.0 247.9 L34.0 272.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M157.9 161.5 Q170.0 147.7 171.2 130.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M228.3 126.5 Q237.7 131.7 248.0 130.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M248.0 130.6 Q257.3 132.2 270.8 127.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M270.8 127.7 Q282.3 136.6 302.4 140.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M302.4 140.2 Q299.4 157.7 307.9 173.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M307.9 173.7 Q299.5 188.7 302.7 207.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M235.4 208.2 Q228.4 204.7 220.6 207.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M220.6 207.7 Q209.0 204.0 193.3 206.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:2.5;stroke-width:1.0"
          pathLength="1"
          d="M193.3 206.7 Q184.4 197.9 167.0 194.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M121.5 198.6 Q129.8 183.8 120.1 171.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M120.1 171.9 Q131.7 160.0 125.6 146.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M125.6 146.9 Q130.8 137.4 118.2 122.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M118.2 122.8 Q147.6 119.1 162.1 107.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M162.1 107.2 Q176.5 112.3 181.1 107.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M205.6 106.2 Q213.4 112.2 217.7 108.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M217.7 108.7 Q226.3 111.3 233.8 104.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M233.8 104.1 Q240.4 108.9 248.3 103.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M304.5 110.0 Q315.4 112.3 340.6 105.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M340.6 105.0 Q334.9 126.8 347.1 141.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M311.6 226.6 Q289.8 221.5 277.8 225.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M255.8 227.9 Q248.2 223.9 243.2 229.8"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M243.2 229.8 Q234.9 224.9 227.0 230.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M204.2 223.4 Q196.7 221.9 183.0 230.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M183.0 230.0 Q174.9 222.3 156.8 224.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:3.5;stroke-width:1.0"
          pathLength="1"
          d="M156.8 224.3 Q153.6 220.3 136.6 225.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M82.6 247.0 Q92.2 226.7 77.3 216.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M70.9 179.3 Q83.9 164.8 71.1 150.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M71.1 150.0 Q92.8 141.0 90.2 127.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M90.2 127.4 Q98.9 129.8 84.2 125.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M84.2 125.6 Q96.1 116.5 84.2 98.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M102.5 81.8 Q134.5 89.5 149.4 83.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M149.4 83.7 Q160.0 92.6 158.0 88.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M167.4 78.5 Q183.8 86.7 191.7 81.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M191.7 81.0 Q205.0 86.5 213.3 78.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M213.3 78.1 Q221.7 89.3 228.1 87.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M228.1 87.1 Q235.0 92.3 242.2 84.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M242.2 84.6 Q243.9 89.7 247.4 81.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M258.9 89.4 Q259.9 94.7 265.6 87.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M265.6 87.4 Q268.8 94.0 278.1 87.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M278.1 87.9 Q281.3 90.1 292.9 79.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M292.9 79.0 Q296.1 86.1 310.1 79.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M310.1 79.2 Q305.6 89.6 313.8 86.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M313.8 86.6 Q324.9 90.7 351.9 81.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M361.8 81.6 Q364.3 93.9 389.5 93.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M389.5 93.4 Q374.8 108.8 384.6 114.0"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M386.2 148.6 Q371.5 152.6 380.7 154.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M397.8 211.8 Q381.1 209.4 390.3 214.4"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M390.3 214.4 Q379.6 221.5 394.3 238.1"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M394.3 238.1 Q371.5 240.3 372.7 255.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M372.7 255.3 Q340.2 244.5 326.3 247.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M291.0 247.9 Q275.0 240.6 266.3 246.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M251.6 251.3 Q244.4 242.4 239.1 246.6"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M239.1 246.6 Q235.5 240.7 232.3 247.7"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M226.5 245.1 Q223.3 241.2 218.4 250.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M218.4 250.3 Q217.0 243.1 212.7 249.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M212.7 249.2 Q207.2 243.7 197.1 251.5"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M197.1 251.5 Q192.5 244.6 180.9 251.3"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M178.2 253.7 Q167.9 247.4 146.3 255.2"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M146.3 255.2 Q155.1 244.3 150.4 246.9"
        />
        <path
          class="ts-grow ts-web"
          style="--l:4.5;stroke-width:1.0"
          pathLength="1"
          d="M150.4 246.9 Q136.6 241.0 106.0 247.9"
        />
        <use href="#ts-padlock" x="436" y="73" width="20" height="20" />
        <use href="#ts-padlock" x="436" y="113" width="20" height="20" />
        <use href="#ts-padlock" x="436" y="201" width="20" height="20" />
        <use href="#ts-padlock" x="436" y="241" width="20" height="20" />
        <path
          class="ts-harm-path"
          d="M233 167 L266.2 178.3 L307.9 173.7 L343.7 164.2 L397.3 179.4 L440 167"
        />
        <path class="ts-grow ts-grow--harm" style="--l:6.2" pathLength="1" d="M440 167 H473" />
        <circle class="ts-harm-dot" cx="486" cy="167" r="13" />
        <text class="ts-bang t-titleXS" x="486" y="173.5" text-anchor="middle">!</text>
      </svg>
      <span class="tschem-actor tschem-actor--other" style="--x:43.1%;--y:54.4%;--w:10%"
        ><Icon name="illustration/circle" size="fill" /></span
      >
    </div>
    <div class="tplate tplate--olive tswap-b" data-color-scheme="light" aria-hidden="true">
      <svg viewBox="0 -5 540 340">
        <path id="ts-cap-0" class="ts-line" d="M109 174 C184 174 200 98 250 98 H470" />
        <text class="ts-label t-body" x="258" y="87">{labels.calendar}</text>

        <circle class="ts-solid" cx="486" cy="98" r="13" />
        <path class="ts-tick" d="M480 98 l4 4.5 l8 -9" />
        <path id="ts-cap-1" class="ts-line" d="M109 174 C184 174 200 146 250 146 H470" />
        <text class="ts-label t-body" x="258" y="135">{labels.note}</text>

        <circle class="ts-solid" cx="486" cy="146" r="13" />
        <path class="ts-tick" d="M480 146 l4 4.5 l8 -9" />
        <path id="ts-cap-2" class="ts-line" d="M109 174 C184 174 200 194 250 194 H470" />
        <text class="ts-label t-body" x="258" y="183">{labels.email}</text>
        <circle class="ts-solid" cx="486" cy="194" r="13" />
        <path class="ts-tick" d="M480 194 l4 4.5 l8 -9" />
        <path id="ts-cap-3" class="ts-line" d="M109 174 C184 174 200 242 250 242 H470" />
        <text class="ts-label t-body" x="258" y="231">{labels.code}</text>

        <circle class="ts-deny" cx="486" cy="242" r="13" />
        <path class="ts-deny-x" d="M481 237 l10 10 m0 -10 l-10 10" />
        <text class="ts-name t-buttonSmall" x="81" y="236" text-anchor="middle">{labels.agent}</text
        >
        <path class="ts-pulse" d="M109 174 C184 174 200 242 250 242 H470"
          ><animate
            begin="indefinite"
            data-motion-delay="1.36"
            attributeName="stroke-dashoffset"
            dur="3.16s"
            repeatCount="indefinite"
            values="38;-387;-387"
            keyTimes="0;0.8416;1"
            calcMode="linear"
          /></path
        >
        <path class="ts-pulse" d="M109 174 C184 174 200 194 250 194 H470"
          ><animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="stroke-dashoffset"
            dur="4.04s"
            repeatCount="indefinite"
            values="38;-255;-255;-369;-369"
            keyTimes="0;0.4533;0.6878;0.8642;1"
            calcMode="linear"
          /></path
        >
        <path class="ts-pulse" d="M109 174 C184 174 200 146 250 146 H470"
          ><animate
            begin="indefinite"
            data-motion-delay="2.16"
            attributeName="stroke-dashoffset"
            dur="3.06s"
            repeatCount="indefinite"
            values="38;-371;-371"
            keyTimes="0;0.8364;1"
            calcMode="linear"
          /></path
        >
        <path class="ts-pulse" d="M109 174 C184 174 200 98 250 98 H470"
          ><animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="stroke-dashoffset"
            dur="3.18s"
            repeatCount="indefinite"
            values="38;-391;-391"
            keyTimes="0;0.8428;1"
            calcMode="linear"
          /></path
        >
        <rect class="ts-echo" x="384" y="182" width="68" height="24" rx="12" opacity="0">
          <animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="x"
            dur="4.04s"
            repeatCount="indefinite"
            values="384;384;370;370"
            keyTimes="0;0.453;0.688;1"
          />
          <animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="y"
            dur="4.04s"
            repeatCount="indefinite"
            values="182;182;170;170"
            keyTimes="0;0.453;0.688;1"
          />
          <animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="width"
            dur="4.04s"
            repeatCount="indefinite"
            values="68;68;96;96"
            keyTimes="0;0.453;0.688;1"
          />
          <animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="height"
            dur="4.04s"
            repeatCount="indefinite"
            values="24;24;48;48"
            keyTimes="0;0.453;0.688;1"
          />
          <animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="rx"
            dur="4.04s"
            repeatCount="indefinite"
            values="12;12;24;24"
            keyTimes="0;0.453;0.688;1"
          />
          <animate
            begin="indefinite"
            data-motion-delay="0"
            attributeName="opacity"
            dur="4.04s"
            repeatCount="indefinite"
            values="0;0;0.6;0;0"
            keyTimes="0;0.453;0.463;0.688;1"
          />
        </rect>
        <rect class="ts-gate" x="384" y="182" width="68" height="24" rx="12" />
        <text class="ts-gate-text t-buttonSmall" x="418" y="199" text-anchor="middle"
          >{labels.ask}</text
        >
      </svg>
      <span class="tschem-actor tschem-actor--logo" style="--x:15%;--y:52.6%;--w:11%"
        ><Icon name="brand/avatar" size="fill" /></span
      >
    </div>
  </div>
</figure>
