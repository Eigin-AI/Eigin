<script lang="ts">
  import { Icon, type IconName } from "@eigin/ui";
  import TeamAgentBlob from "./TeamAgentBlob.svelte";
  import type { TeamDiagramLabels } from "../../content/home/types";

  let { labels, active = false }: { labels: TeamDiagramLabels; active?: boolean } = $props();
  const agents = [
    { x: 270, y: 55, icon: "illustration/moon" as IconName, from: [270, 95], to: [270, 148] },
    { x: 465, y: 175, icon: "illustration/bird" as IconName, from: [368, 194], to: [425, 182] },
    { x: 390, y: 355, icon: "illustration/flower" as IconName, from: [363, 323], to: [320, 260] },
    { x: 150, y: 355, icon: "illustration/octopus" as IconName, from: [232, 260], to: [177, 323] },
    { x: 75, y: 175, icon: "illustration/tree" as IconName, from: [115, 182], to: [176, 194] },
  ].map((agent, index) => {
    const node = index % 2 === 0 ? agent.from : agent.to;
    const hub = index % 2 === 0 ? agent.to : agent.from;
    return {
      ...agent,
      incoming: `M${node[0]} ${node[1]} L${hub[0]} ${hub[1]}`,
      outgoing: `M${hub[0]} ${hub[1]} L${node[0]} ${node[1]}`,
      length: Math.hypot(hub[0] - node[0], hub[1] - node[1]),
    };
  });
  const pulseLength = 32;

  // Each contribution becomes a reply to another agent before the next pair starts.
  const exchanges = [
    [0, 4],
    [4, 2],
    [2, 1],
    [1, 3],
    [3, 0],
  ];
  const exchangeDuration = 2.8;
  const travelDuration = 0.65;
  const sendAt = 0.35;
  let elapsed = $state(0);
  const exchange = $derived(exchanges[Math.floor(elapsed / exchangeDuration) % exchanges.length]);
  const sender = $derived(exchange[0]);
  const recipient = $derived(exchange[1]);
  const phase = $derived(elapsed % exchangeDuration);
  const receivedAt = $derived(arrival(sendAt, agents[sender].length));
  const replyGlimmerAt = $derived(receivedAt + 0.42);
  const replyAt = $derived(replyGlimmerAt + 0.27);
  const deliveredAt = $derived(arrival(replyAt, agents[recipient].length));

  function arrival(start: number, length: number): number {
    return start + travelDuration * ((length + 4) / (length + pulseLength + 8));
  }

  function pulse(index: number) {
    const start = index === sender ? sendAt : replyAt;
    const progress = Math.min(1, Math.max(0, (phase - start) / travelDuration));
    return {
      visible:
        active &&
        (index === sender || index === recipient) &&
        phase >= start &&
        phase < start + travelDuration,
      offset: pulseLength + 4 - progress * (agents[index].length + pulseLength + 8),
    };
  }

  function wobbling(index: number): boolean {
    if (!active || (index !== sender && index !== recipient)) return false;
    const event = index === sender ? sendAt : deliveredAt;
    return phase >= event - 0.25 && phase < event + 0.2;
  }

  function tint(start: number): number {
    const progress = (phase - start) / 0.28;
    return progress > 0 && progress < 1 ? Math.sin(progress * Math.PI) ** 2 * 40 : 0;
  }

  // The stack receives front-to-back, then replies back-to-front.
  function glimmer(layer: number): number {
    if (!active) return 0;
    return Math.max(tint(receivedAt + layer * 0.065), tint(replyGlimmerAt + (2 - layer) * 0.065));
  }

  $effect(() => {
    if (!active) return;
    let previous = performance.now();
    let frame = requestAnimationFrame(function tick(now) {
      elapsed += Math.max(0, Math.min((now - previous) / 1000, 0.1));
      previous = now;
      frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  });
</script>

<figure role="img" aria-label={labels.description}>
  <svg viewBox="0 0 540 420" aria-hidden="true">
    {#each agents as agent, index}
      {@const flow = pulse(index)}
      <path class="connection" d={agent.incoming} />
      <path
        class="flow"
        d={index === sender ? agent.incoming : agent.outgoing}
        stroke-dasharray="{pulseLength} {agent.length + pulseLength * 2}"
        stroke-dashoffset={flow.offset}
        opacity={flow.visible ? 1 : 0}
      />
    {/each}

    <g>
      <rect
        class="context-sheet context-sheet--back"
        style="--glimmer: {glimmer(2)}%"
        x="188"
        y="148"
        width="180"
        height="100"
        rx="12"
      />
      <rect
        class="context-sheet context-sheet--middle"
        style="--glimmer: {glimmer(1)}%"
        x="182"
        y="154"
        width="180"
        height="100"
        rx="12"
      />
      <rect
        class="context-sheet"
        style="--glimmer: {glimmer(0)}%"
        x="176"
        y="160"
        width="180"
        height="100"
        rx="12"
      />
      <text class="context-label t-titleS" x="266" y="202" text-anchor="middle">
        <tspan x="266">{labels.context[0]}</tspan>
        <tspan x="266" dy="30">{labels.context[1]}</tspan>
      </text>
    </g>

    {#each agents as agent, index}
      <foreignObject x={agent.x - 56} y={agent.y - 56} width="112" height="112">
        <TeamAgentBlob seed={index} engaged={wobbling(index)} />
      </foreignObject>
      <foreignObject x={agent.x - 22} y={agent.y - 22} width="44" height="44">
        <span class="agent-illustration"><Icon name={agent.icon} size={44} /></span>
      </foreignObject>
    {/each}
  </svg>
</figure>

<style>
  figure {
    margin: 0;
    width: 100%;
    color: var(--color-text-standard-base);
  }
  svg {
    display: block;
    width: 100%;
    height: auto;
    overflow: visible;
  }
  .connection {
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    opacity: 0.25;
  }
  .flow {
    fill: none;
    stroke: var(--color-surface-standard-elevated);
    stroke-width: 5;
    stroke-linecap: round;
  }
  .context-sheet {
    fill: color-mix(
      in srgb,
      var(--color-surface-impact-coral) var(--glimmer, 0%),
      var(--sheet, var(--color-icon-standard-base))
    );
  }
  .context-sheet--back {
    --sheet: var(--color-icon-standard-base);
    opacity: 0.135;
  }
  .context-sheet--middle {
    opacity: 0.4125;
  }
  .context-label {
    fill: var(--color-surface-standard-elevated);
  }
  .agent-illustration {
    display: flex;
    color: var(--color-surface-standard-elevated);
  }
  @media (prefers-reduced-motion: reduce) {
    .flow {
      display: none;
    }
  }
</style>
