<script lang="ts">
  import { SvelteMap } from "svelte/reactivity";
  import { Icon } from "@lib";
  import { icons, type IconName } from "@lib/generated/icons";

  const groups = $derived.by(() => {
    const byLayer = new SvelteMap<string, IconName[]>();
    for (const name of Object.keys(icons) as IconName[]) {
      const layer = name.split("/")[0];
      const list = byLayer.get(layer) ?? [];
      list.push(name);
      byLayer.set(layer, list);
    }
    return [...byLayer.entries()].map(([label, names]) => ({ label, names }));
  });
</script>

<div class="doc">
  {#each groups as group (group.label)}
    <h2 class="t-titleM">{group.label}</h2>
    <div class="grid">
      {#each group.names as name (name)}
        <div class="cell" title={name}>
          <span class="glyph"><Icon {name} size={28} /></span>
          <span class="name">{name}</span>
        </div>
      {/each}
    </div>
  {/each}
</div>

<style>
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
    gap: var(--spacing-n16);
  }

  .cell {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n16);
    padding: var(--spacing-n16);
    text-align: center;
  }

  /* The same quiet mono the colour page sets its hex codes in. */
  /* Paths run long, so they break rather than reach into the next cell. */
  .name {
    color: var(--color-text-standard-muted);
    font-family: var(--font-mono);
    font-size: 11px;
    line-height: 1.5;
    overflow-wrap: anywhere;
  }

  .glyph {
    color: var(--color-icon-standard-base);
    display: inline-flex;
  }
</style>
