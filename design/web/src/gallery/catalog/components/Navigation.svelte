<script lang="ts">
  import {
    BrandAvatar,
    NavigationBar,
    NavigationHeader,
    NavigationTab,
    ActionButton,
    Icon,
  } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let background = $state("surface");
  let selected = $state("chat");

  const tabs = [
    { id: "chat", label: "Eigin", icon: "brand/avatar" },
    { id: "spaces", label: "Spaces", icon: "brand/security" },
    { id: "settings", label: "Settings", icon: "brand/settings" },
  ] as const;

  let headerVariant = $state("avatar");
</script>

<div class="doc">
  <h2 class="t-titleM">Navigation Bar</h2>
  <div class="controls">
    <OptionSelector options={["surface", "clear"]} bind:value={background} />
  </div>
  <div class="phone bottom">
    <NavigationBar background={background as "surface" | "clear"}>
      {#each tabs as tab (tab.id)}
        <NavigationTab
          label={tab.label}
          selected={selected === tab.id}
          onclick={() => (selected = tab.id)}
        >
          {#snippet icon()}
            <Icon name={tab.icon} size="fill" />
          {/snippet}
        </NavigationTab>
      {/each}
    </NavigationBar>
  </div>

  <h2 class="t-titleM">Navigation Header</h2>
  <div class="controls">
    <OptionSelector options={["avatar", "title", "leading only"]} bind:value={headerVariant} />
  </div>
  <div class="phone top">
    {#if headerVariant === "avatar"}
      <NavigationHeader>
        {#snippet leading()}
          <ActionButton icon="functional/note" variant="open" size="medium" label="New note" />
        {/snippet}
        {#snippet center()}
          <BrandAvatar>
            <Icon name="brand/avatar" size="fill" />
          </BrandAvatar>
        {/snippet}
        {#snippet trailing()}
          <ActionButton icon="functional/phone" variant="open" size="medium" label="Call" />
        {/snippet}
      </NavigationHeader>
    {:else if headerVariant === "title"}
      <NavigationHeader title="Paging Agent Registry">
        {#snippet leading()}
          <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
        {/snippet}
      </NavigationHeader>
    {:else}
      <NavigationHeader>
        {#snippet leading()}
          <ActionButton icon="functional/arrow/left" variant="open" size="medium" label="Back" />
        {/snippet}
      </NavigationHeader>
    {/if}
  </div>

  <h2 class="t-titleM">Brand Avatar</h2>
  <div class="row">
    <BrandAvatar>
      <Icon name="brand/avatar" size="fill" />
    </BrandAvatar>
    <BrandAvatar size={40} inset={6}>
      <Icon name="brand/security" size="fill" />
    </BrandAvatar>
    <BrandAvatar onclick={() => {}} label="Open profile">
      <Icon name="brand/settings" size="fill" />
    </BrandAvatar>
  </div>
</div>

<style>
  .controls {
    margin-bottom: var(--spacing-n16);
  }

  .phone {
    width: 393px;
    background: var(--color-surface-standard-alternative);
    border-radius: var(--radius-card);
    overflow: hidden;
    margin-bottom: var(--spacing-n40);
  }

  .phone.bottom {
    padding-top: var(--spacing-n48);
  }

  .phone.top {
    padding-bottom: var(--spacing-n48);
  }

  .row {
    display: flex;
    align-items: center;
    gap: var(--spacing-n24);
  }
</style>
