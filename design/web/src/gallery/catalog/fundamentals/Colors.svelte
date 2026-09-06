<script lang="ts">
  import { SvelteMap } from "svelte/reactivity";
  import { colorTokens, type ColorToken } from "@lib";

  const groups = $derived.by(() => {
    const byLayer = new SvelteMap<string, ColorToken[]>();
    for (const token of colorTokens) {
      const layer = token.name.split(".")[0];
      const list = byLayer.get(layer) ?? [];
      list.push(token);
      byLayer.set(layer, list);
    }
    return [...byLayer.entries()].map(([label, swatches]) => ({ label, swatches }));
  });
</script>

<div class="doc">
  {#each groups as group (group.label)}
    <h2 class="t-titleM">{group.label}</h2>
    <div class="swatches">
      {#each group.swatches as token (token.name)}
        <div class="swatch" title="{token.name} — {token.light} / {token.dark}">
          <div
            class="chip"
            style="background: var(--color-{token.name.split('.').join('-')})"
          ></div>
          <div class="label">
            <div class="t-titleXS">{token.name}</div>
            <div class="hex">
              {token.light}
              {#if token.dark !== token.light}/ {token.dark}{/if}
            </div>
          </div>
        </div>
      {/each}
    </div>
  {/each}
</div>

<style>
  /* Sized to the longest token path at titleXS (241px) plus the chip and its
     gap, so a name never runs into the swatch beside it. */
  .swatches {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: var(--spacing-n24) var(--spacing-n16);
  }

  .swatch {
    display: flex;
    gap: var(--spacing-n16);
    align-items: center;
  }

  .chip {
    width: 48px;
    height: 48px;
    border-radius: var(--radius-full);
    box-shadow: 0 2px 6px rgb(0 0 0 / 0.25);
    flex: none;
  }

  .label {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n4);
  }

  .hex {
    color: var(--color-text-standard-muted);
    font-family: var(--font-mono);
    font-size: 11px;
  }
</style>
