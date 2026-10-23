<script lang="ts">
  import type { Snippet } from "svelte";
  import { ActionButton, NavigationHeader } from "@lib";
  import ScreenScroll from "../ScreenScroll.svelte";

  let {
    title,
    back = "agent",
    children,
    trailing: trailingContent,
    onBack,
  }: {
    title: string;
    back?: string;
    onBack?: () => void;
    children: Snippet;
    trailing?: Snippet;
  } = $props();
</script>

<div class="secondary-screen">
  <ScreenScroll>
    {#snippet header()}
      <NavigationHeader {title}>
        {#snippet leading()}
          <ActionButton
            icon="functional/arrow/left"
            variant="open"
            size="medium"
            label="Back"
            onclick={() => {
              if (onBack) onBack();
              else location.hash = `#/screens/${back}`;
            }}
          />
        {/snippet}
        {#snippet trailing()}{#if trailingContent}{@render trailingContent()}{/if}{/snippet}
      </NavigationHeader>
    {/snippet}
    {@render children()}
  </ScreenScroll>
</div>

<style>
  .secondary-screen {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    background: var(--color-surface-standard-base);
  }
</style>
