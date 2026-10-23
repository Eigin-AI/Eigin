<script lang="ts">
  import Icon from "../icon/Icon.svelte";

  let {
    label,
    value = $bindable(""),
    isError = false,
    errorMessage = "",
    isSecure = false,
  }: {
    label: string;
    value?: string;
    isError?: boolean;
    errorMessage?: string;
    /** Renders a password field. */
    isSecure?: boolean;
  } = $props();

  let focused = $state(false);

  /* The label floats once the field is focused or holds text. */
  const isActive = $derived(focused || value.length > 0);

  let field = $state<HTMLInputElement>();
</script>

<!--
  A capsule field whose single label animates between
  the resting and floating positions, with the input revealed underneath.
-->
<div class="wrapper">
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="field" class:error={isError} onclick={() => field?.focus()}>
    <div class="stack" class:active={isActive}>
      <span class="label" class:floating={isActive}>{label}</span>
      <input
        bind:this={field}
        bind:value
        aria-label={label}
        type={isSecure ? "password" : "text"}
        class="t-description"
        onfocus={() => (focused = true)}
        onblur={() => (focused = false)}
      />
    </div>

    <!-- Check while filled and valid; info while in error. -->
    <span class="trailing">
      <span class="glyph check" class:visible={value.length > 0 && !isError}>
        <Icon name="functional/check" size={24} />
      </span>
      <span class="glyph info" class:visible={isError}>
        <Icon name="functional/info" size={24} />
      </span>
    </span>
  </div>

  {#if isError && errorMessage}
    <span class="message t-description">{errorMessage}</span>
  {/if}
</div>

<style>
  .wrapper {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n12);
  }

  .field {
    position: relative;
    display: flex;
    align-items: center;
    box-sizing: border-box;
    height: var(--sizing-input-height);
    padding: 0 var(--sizing-input-px-left);
    border-radius: var(--radius-full);
    background: var(--color-input-standard-active);
    cursor: text;
    transition: box-shadow var(--motion-normal) var(--motion-easing-smooth);
  }

  .field::before {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: var(--color-interaction-light-hover);
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
    pointer-events: none;
  }

  .field:hover::before {
    opacity: 1;
  }

  .field.error {
    box-shadow: inset 0 0 0 1px var(--color-interaction-border-error);
  }

  .stack {
    position: relative;
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
    gap: 0;
    transition: gap var(--motion-normal) var(--motion-easing-smooth);
  }

  .stack.active {
    gap: var(--spacing-n4);
  }

  /* One label that animates between the two typography styles. */
  .label {
    color: var(--color-text-standard-muted);
    font-family: var(--font-ui);
    font-size: 18px;
    line-height: 20.8px;
    transition:
      font-size var(--motion-normal) var(--motion-easing-smooth),
      line-height var(--motion-normal) var(--motion-easing-smooth);
    text-box: trim-both cap alphabetic;
  }

  .label.floating {
    /* Typography.note */
    font-size: 14px;
    line-height: 16.8px;
  }

  input {
    border: none;
    background: transparent;
    padding: 0;
    color: var(--color-text-standard-base);
    width: 100%;
    height: 0;
    opacity: 0;
    transition:
      height var(--motion-normal) var(--motion-easing-smooth),
      opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .stack.active input {
    height: 21px;
    opacity: 1;
  }

  input:focus {
    outline: none;
  }

  .trailing {
    position: relative;
    width: 24px;
    height: 24px;
    flex: none;
  }

  .glyph {
    position: absolute;
    inset: 0;
    display: inline-flex;
    opacity: 0;
    transition: opacity var(--motion-normal) var(--motion-easing-smooth);
  }

  .glyph.visible {
    opacity: 1;
  }

  .glyph.check {
    color: var(--color-icon-standard-base);
  }

  .glyph.info {
    color: var(--color-text-standard-base);
  }

  .message {
    color: var(--color-text-standard-error);
    padding: 0 var(--spacing-n24);
  }
</style>
