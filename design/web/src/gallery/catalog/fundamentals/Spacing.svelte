<script lang="ts">
  import { SvelteMap } from "svelte/reactivity";
  import { ContentGroup, Row, scaleGroups } from "@lib";
  import DeviceFrame from "@gallery/frames/DeviceFrame.svelte";

  const spacing = $derived(scaleGroups.find((g) => g.name === "spacing")?.tokens ?? []);
  const radius = $derived(scaleGroups.find((g) => g.name === "radius")?.tokens ?? []);
  const strokes = $derived(scaleGroups.find((g) => g.name === "strokeWeight")?.tokens ?? []);

  /* Representative frame widths per breakpoint — illustration only, so the
     grid can be drawn to scale. The breakpoint values themselves are tokens. */
  const frameWidth: Record<string, number> = { mobile: 393, tablet: 834, desktop: 1440 };

  interface Breakpoint {
    name: string;
    columns: number;
    gutter: number;
    inner: number;
    outer: number;
    width: number;
  }

  const breakpoints = $derived.by<Breakpoint[]>(() => {
    const tokens = scaleGroups.find((g) => g.name === "grid")?.tokens ?? [];
    const byName = new SvelteMap<string, Partial<Breakpoint>>();
    for (const token of tokens) {
      const [name, field] = token.name.split(".");
      const entry = byName.get(name) ?? { name, width: frameWidth[name] ?? 393 };
      byName.set(name, { ...entry, [field]: token.value });
    }
    return [...byName.values()] as Breakpoint[];
  });
</script>

<div class="doc">
  <h2 class="t-titleM">Spacing</h2>
  <div class="scale">
    {#each spacing as token (token.name)}
      <div class="stack">
        <span class="bar" style:height="{token.value}px"></span>
        <span class="meta">{token.name}</span>
        <span class="meta">{token.value}</span>
      </div>
    {/each}
  </div>

  <h2 class="t-titleM">Radius</h2>
  <div class="samples">
    {#each radius as token (token.name)}
      <div class="stack">
        <span class="radius-box" style:border-radius="{token.value}px"></span>
        <span class="meta">{token.name}</span>
        <span class="meta">{token.value}px</span>
      </div>
    {/each}
  </div>

  <h2 class="t-titleM">Stroke weight</h2>
  <div class="samples">
    {#each strokes as token (token.name)}
      <div class="stack">
        <span class="stroke" style:height="{token.value}px"></span>
        <span class="meta">{token.name}</span>
        <span class="meta">{token.value}px</span>
      </div>
    {/each}
  </div>

  <h2 class="t-titleM">Grid</h2>
  <p class="lede t-description">
    A two-part margin. The outer one is how far a view may fill; the inner one is where content
    starts. Columns sit inside it, split by gutters. The numbers follow the width of the box a
    layout is in, not the window.
  </p>

  <table>
    <thead>
      <tr><th>Breakpoint</th><th>Columns</th><th>Gutter</th><th>Inner</th><th>Outer</th></tr>
    </thead>
    <tbody>
      {#each breakpoints as bp (bp.name)}
        <tr>
          <td>{bp.name}</td>
          <td>{bp.columns}</td>
          <td>{bp.gutter}px</td>
          <td>{bp.inner}px</td>
          <td>{bp.outer}px</td>
        </tr>
      {/each}
    </tbody>
  </table>

  <p class="lede t-description">
    Read it over something real: the grid button in the corner of any screen lays it on top. Tinted
    is what the grid reserves, so content should sit in the clear.
  </p>

  <div class="canvas">
    <DeviceFrame height="content" colorScheme="inherit" grid>
      <div class="demo">
        <ContentGroup label="General">
          <Row title="Language" value="English" onclick={() => {}} />
          <Row title="Send feedback" onclick={() => {}} />
        </ContentGroup>
      </div>
    </DeviceFrame>
  </div>
</div>

<style>
  .scale {
    display: flex;
    align-items: flex-end;
    gap: var(--spacing-n12);
    flex-wrap: wrap;
  }

  .samples {
    display: flex;
    align-items: flex-end;
    gap: var(--spacing-n32);
    flex-wrap: wrap;
  }

  .stack {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n4);
  }

  .bar {
    width: 24px;
    background: var(--color-icon-standard-base);
    border-radius: 2px;
  }

  .meta {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--color-text-standard-muted);
  }

  .radius-box {
    width: 160px;
    height: 96px;
    background: var(--color-icon-standard-base);
  }

  .stroke {
    width: 160px;
    background: var(--color-icon-standard-base);
  }

  .demo {
    padding: var(--spacing-n16) 0;
  }

  .lede {
    max-width: 60ch;
    color: var(--color-text-standard-muted);
  }

  table {
    border-collapse: collapse;
    margin-bottom: var(--spacing-n32);
    font-size: 13px;
  }

  th,
  td {
    text-align: left;
    padding: var(--spacing-n8) var(--spacing-n24) var(--spacing-n8) 0;
    border-bottom: 1px solid var(--color-border-standard-base);
  }

  th {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 400;
    color: var(--color-text-standard-muted);
  }
</style>
