<script lang="ts">
  import { Icon } from "@lib";
  import { flip } from "svelte/animate";
  import { fade, scale } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import { onMount, untrack } from "svelte";
  import { knowledgeIcons, type GraphEntity } from "./sampleGraph";

  let {
    center,
    related,
    onSelect,
    onDetails,
    onCapacity,
  }: {
    center: GraphEntity;
    related: GraphEntity[];
    onSelect: (id: string) => void;
    onDetails: () => void;
    onCapacity: (count: number) => void;
  } = $props();
  let canvas: HTMLDivElement;
  let width = $state(360);
  let height = $state(400);
  let reduced = $state(false);
  const compact = $derived(height < 300);
  const duration = $derived(reduced ? 0 : 300);
  // Explicit arrangements keep small neighborhoods balanced rather than
  // occupying a partial ring. Coordinates describe the whole icon-label node.
  const arrangements: Record<number, number[][]> = {
    0: [],
    1: [[50, 14]],
    2: [
      [50, 14],
      [50, 86],
    ],
    3: [
      [50, 14],
      [18, 76],
      [82, 76],
    ],
    4: [
      [18, 24],
      [82, 24],
      [18, 76],
      [82, 76],
    ],
    5: [
      [50, 14],
      [18, 30],
      [82, 30],
      [18, 76],
      [82, 76],
    ],
    6: [
      [18, 30],
      [50, 18],
      [82, 30],
      [18, 70],
      [50, 82],
      [82, 70],
    ],
  };
  const slots = $derived.by(() => {
    if (height < 192 && width >= 440 && related.length <= 4) {
      const shortArrangements: Record<number, number[][]> = {
        0: [],
        1: [[20, 50]],
        2: [
          [20, 50],
          [80, 50],
        ],
        3: [
          [10, 35],
          [28, 65],
          [80, 50],
        ],
        4: [
          [10, 35],
          [28, 65],
          [72, 35],
          [90, 65],
        ],
      };
      return shortArrangements[related.length];
    }
    const arrangement = arrangements[related.length] ?? arrangements[6];
    // Turn the top position left when the canvas has more horizontal space.
    return width > height ? arrangement.map(([x, y]) => [y, 100 - x]) : arrangement;
  });
  const nodeY = (percent: number) =>
    Math.max(compact ? 48 : 56, Math.min(height - (compact ? 48 : 56), (height * percent) / 100));
  const nodes = $derived([
    { entity: center, x: 50, y: 50, focus: true },
    ...related.map((entity, index) => ({
      entity,
      x: slots[index % slots.length][0],
      y: slots[index % slots.length][1],
      focus: false,
    })),
  ]);
  type PlacedNode = (typeof nodes)[number];
  let shown = $state<PlacedNode[]>([]);
  let transitioning = $state(false);
  let movingLines = $state(false);
  let stationaryFocusID = $state<string | null>(null);
  let revealed = $state(new Set<string>());
  let exitDelays = new Map<string, number>();
  let entryDelays = new Map<string, number>();
  const staggerStep = 25;
  const scaleDuration = 120;
  const pause = 15;

  function enter(element: Element, id: string) {
    return scale(element, {
      duration: reduced ? 0 : scaleDuration,
      delay: reduced ? 0 : (entryDelays.get(id) ?? 0),
      start: 0,
      opacity: 1,
      easing: cubicOut,
    });
  }
  function leave(element: Element, id: string) {
    return scale(element, {
      duration: reduced ? 0 : scaleDuration,
      delay: reduced ? 0 : (exitDelays.get(id) ?? 0),
      start: 0,
      opacity: 1,
      easing: cubicOut,
    });
  }
  function delays(ids: string[]) {
    return new Map(
      ids.map((id, index) => [id, index * staggerStep + Math.round(Math.random() * 10)]),
    );
  }
  function finishTime(schedule: Map<string, number>) {
    return schedule.size ? Math.max(...schedule.values()) + scaleDuration + pause : 0;
  }

  // Remove → move → introduce. Keyed surviving nodes remain mounted and opaque.
  // Cleanup cancels every pending phase when navigation or viewport changes.
  $effect(() => {
    const target = nodes;
    const immediate = reduced;
    return untrack(() => {
      if (immediate) {
        shown = target;
        revealed = new Set(target.map((node) => node.entity.id));
        movingLines = false;
        transitioning = false;
        return;
      }
      const previousIDs = new Set(shown.map((node) => node.entity.id));
      const targetIDs = new Set(target.map((node) => node.entity.id));
      const leaving = shown.filter((node) => !targetIDs.has(node.entity.id));
      const arriving = target.filter((node) => !previousIDs.has(node.entity.id));
      const retained = target.filter((node) => previousIDs.has(node.entity.id));
      const moving = retained.some((node) => {
        const previous = shown.find((old) => old.entity.id === node.entity.id)!;
        return previous.x !== node.x || previous.y !== node.y || previous.focus !== node.focus;
      });
      const focus = target.find((node) => node.focus);
      const previousFocus = shown.find((node) => node.focus);
      stationaryFocusID =
        focus &&
        previousFocus &&
        focus.entity.id === previousFocus.entity.id &&
        focus.x === previousFocus.x &&
        focus.y === previousFocus.y &&
        revealed.has(focus.entity.id)
          ? focus.entity.id
          : null;
      revealed = new Set([...revealed].filter((id) => targetIDs.has(id)));
      movingLines = true;
      const lineExitTime = shown.length ? 100 : 0;
      exitDelays = new Map(leaving.map((node) => [node.entity.id, 0]));
      entryDelays = delays(arriving.map((node) => node.entity.id));
      transitioning = true;
      const timers: ReturnType<typeof setTimeout>[] = [];
      const later = (callback: () => void, delay: number) => {
        if (!delay) callback();
        else timers.push(setTimeout(callback, delay));
      };
      shown = shown.filter((node) => targetIDs.has(node.entity.id));
      later(
        () => {
          shown = retained;
          later(
            () => {
              movingLines = false;
              shown = target;
              later(() => (transitioning = false), finishTime(entryDelays));
            },
            moving ? duration + pause : 0,
          );
        },
        Math.max(lineExitTime, finishTime(exitDelays)),
      );
      return () => timers.forEach(clearTimeout);
    });
  });
  // Each button includes a fixed two-line label beneath the circle.
  const labelOffset = 20;
  onMount(() => {
    const observer = new ResizeObserver(([entry]) => {
      width = entry.contentRect.width;
      height = entry.contentRect.height;
      onCapacity(entry.contentRect.height < 300 ? 4 : 6);
    });
    observer.observe(canvas);
    const media = matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => (reduced = media.matches);
    update();
    media.addEventListener("change", update);
    return () => {
      observer.disconnect();
      media.removeEventListener("change", update);
    };
  });
</script>

<div
  class="graph-canvas"
  class:compact
  bind:this={canvas}
  aria-label={`Relationships for ${center.name}`}
>
  <svg class="edges" aria-hidden="true" viewBox={`0 0 ${width} ${height}`}>
    {#each shown.filter((node) => !node.focus && !movingLines && revealed.has(node.entity.id) && revealed.has(center.id)) as node (node.entity.id)}
      <line
        in:fade={{ duration: reduced ? 0 : 120 }}
        out:fade={{ duration: reduced ? 0 : 100 }}
        x1={width / 2}
        y1={nodeY(50) - labelOffset}
        x2={(width * node.x) / 100}
        y2={nodeY(node.y) - labelOffset}
      />
    {/each}
  </svg>
  {#each shown as node (node.entity.id)}
    <button
      class="graph-node"
      class:focused={node.focus}
      style:left={`${node.x}%`}
      style:top={`${nodeY(node.y)}px`}
      aria-label={node.focus
        ? `View details for ${node.entity.name}`
        : `Explore ${node.entity.name}`}
      title={node.entity.name}
      disabled={transitioning || shown.some((item) => !revealed.has(item.entity.id))}
      onclick={(event) => {
        if (node.focus) onDetails();
        else onSelect(node.entity.id);
        event.currentTarget.focus();
      }}
      animate:flip={{ duration, easing: cubicOut }}
      onintroend={() => {
        if (shown.some((item) => item.entity.id === node.entity.id))
          revealed = new Set([...revealed, node.entity.id]);
      }}
      in:enter={node.entity.id}
      out:leave={node.entity.id}
    >
      <span class="circle"
        ><Icon name={knowledgeIcons[node.entity.kind]} size={node.focus ? 32 : 24} /></span
      >
      <span
        class="node-label t-tag"
        class:label-hidden={(movingLines && node.entity.id !== stationaryFocusID) ||
          !revealed.has(node.entity.id)}>{node.entity.name}</span
      >
    </button>
  {/each}
</div>

<style>
  .graph-canvas {
    position: relative;
    flex: 1;
    min-height: 0;
    width: 100%;
  }
  .edges {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }
  line {
    stroke: var(--color-border-standard-base);
    stroke-opacity: 0.8;
    stroke-width: 1.5;
  }
  .graph-node {
    position: absolute;
    transform: translate(-50%, -50%);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: flex-start;
    box-sizing: border-box;
    gap: var(--spacing-n8);
    width: 88px;
    height: 112px;
    padding: 12px 0 0;
    border: none;
    background: none;
    cursor: pointer;
    color: var(--color-text-standard-muted);
  }
  .circle {
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 48px;
    height: 48px;
    border-radius: var(--radius-full);
    background: var(--color-surface-standard-alternative);
    color: var(--color-icon-standard-base);
    transition:
      width var(--motion-normal),
      height var(--motion-normal),
      background var(--motion-normal);
  }
  .focused .circle {
    width: 72px;
    height: 72px;
    background: var(--color-button-spot-base);
    color: var(--color-icon-impact-base);
  }
  .focused {
    padding-top: 0;
    color: var(--color-text-standard-base);
  }
  .node-label.label-hidden {
    opacity: 0;
    transition-duration: 80ms;
  }
  .node-label {
    transition: opacity 120ms linear;
    width: 80px;
    height: 32px;
    line-height: 16px;
    text-box: normal;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    overflow-wrap: anywhere;
    text-align: center;
  }
  .graph-node:focus-visible {
    outline: 2px solid var(--color-icon-standard-base);
    outline-offset: 4px;
    border-radius: var(--radius-card);
  }
  .compact .graph-node {
    padding-top: 0;
    height: 80px;
  }
  .compact .circle {
    width: 40px;
    height: 40px;
  }
  .compact .focused {
    height: 96px;
  }
  .compact .focused .circle {
    width: 56px;
    height: 56px;
  }
  @media (prefers-reduced-motion: reduce) {
    .circle {
      transition: none;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .node-label {
      transition: none;
    }
  }
</style>
