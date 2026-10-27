<script lang="ts">
  import { Icon } from "@lib";
  import type { ButtonSize, ButtonVariant } from "@lib";
  import {
    Button,
    ActionButton,
    SubtleActionButton,
    CheckboxButton,
    SelectorButton,
    Tag,
  } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  const variants: ButtonVariant[] = [
    "primary",
    "secondary",
    "elevated",
    "outline",
    "spot",
    "destructive",
    "open",
  ];
  const sizes: ButtonSize[] = ["large", "medium", "small", "extraSmall"];
  const states = ["enabled", "disabled"] as const;

  let btnVariant = $state<ButtonVariant>("primary");
  let btnSize = $state<ButtonSize>("large");
  let btnState = $state<(typeof states)[number]>("enabled");
  let btnTrailing = $state("no trailing");

  let actionVariant = $state<ButtonVariant>("primary");
  let actionSize = $state<ButtonSize>("large");

  let subtleSize = $state<ButtonSize>("large");

  let checkboxPick = $state("checked");
  let checkboxState = $state<(typeof states)[number]>("enabled");

  let selectorPick = $state("selected");
  let selectorState = $state<(typeof states)[number]>("enabled");

  const tagKinds = ["plain", "trailing check", "trailing x"] as const;
  let tagKind = $state<(typeof tagKinds)[number]>("plain");
  let tagState = $state<(typeof states)[number]>("enabled");
</script>

<div class="doc">
  {#snippet trailingPlus()}
    <Icon name="functional/plus" size={24} />
  {/snippet}
  {#snippet trailingCheck()}
    <Icon name="functional/check" size={16} />
  {/snippet}
  {#snippet trailingX()}
    <Icon name="functional/x" size={16} />
  {/snippet}

  <h2 class="t-titleM">Button</h2>
  <div class="controls">
    <OptionSelector options={variants} bind:value={btnVariant} />
    <OptionSelector options={sizes} bind:value={btnSize} />
    <OptionSelector options={states} bind:value={btnState} />
    <OptionSelector options={["no trailing", "trailing +"]} bind:value={btnTrailing} />
  </div>
  <div class="specimen">
    <Button
      label="Action text"
      variant={btnVariant}
      size={btnSize}
      disabled={btnState === "disabled"}
      trailing={btnTrailing === "trailing +" ? trailingPlus : undefined}
    />
  </div>

  <h2 class="t-titleM">Action button</h2>
  <div class="controls">
    <OptionSelector options={variants} bind:value={actionVariant} />
    <OptionSelector options={sizes} bind:value={actionSize} />
  </div>
  <div class="specimen">
    <ActionButton icon="functional/plus" variant={actionVariant} size={actionSize} />
  </div>

  <h2 class="t-titleM">Subtle action button</h2>
  <div class="controls">
    <OptionSelector options={sizes} bind:value={subtleSize} />
  </div>
  <div class="specimen">
    <SubtleActionButton label="Action" size={subtleSize}>
      {#snippet icon()}<Icon name="functional/plus" size={24} />{/snippet}
    </SubtleActionButton>
  </div>

  <h2 class="t-titleM">Checkbox button</h2>
  <div class="controls">
    <OptionSelector options={["checked", "unchecked"]} bind:value={checkboxPick} />
    <OptionSelector options={states} bind:value={checkboxState} />
  </div>
  <div class="specimen">
    <CheckboxButton
      label="Action text"
      isChecked={checkboxPick === "checked"}
      disabled={checkboxState === "disabled"}
    />
  </div>

  <h2 class="t-titleM">Selector button</h2>
  <div class="controls">
    <OptionSelector options={["selected", "unselected"]} bind:value={selectorPick} />
    <OptionSelector options={states} bind:value={selectorState} />
  </div>
  <div class="specimen">
    <SelectorButton
      label="Action text"
      isSelected={selectorPick === "selected"}
      disabled={selectorState === "disabled"}
    />
  </div>

  <h2 class="t-titleM">Tag</h2>
  <div class="controls">
    <OptionSelector options={tagKinds} bind:value={tagKind} />
    <OptionSelector options={states} bind:value={tagState} />
  </div>
  <div class="specimen">
    <Tag
      label={tagKind === "trailing x" ? "Family & School" : "Action text"}
      disabled={tagState === "disabled"}
      trailing={tagKind === "trailing check"
        ? trailingCheck
        : tagKind === "trailing x"
          ? trailingX
          : undefined}
    />
  </div>
</div>

<style>
  /* Large buttons fill their container, so give specimens the phone column. */
  .specimen {
    max-width: 345px;
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
  }

  .specimen {
    padding: var(--spacing-n24);
    margin-bottom: var(--spacing-n40);
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-base);
    display: flex;
    justify-content: center;
  }
</style>
