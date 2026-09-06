<script lang="ts">
  import { TextInput, ChatInput } from "@lib";
  import type { MicState } from "@lib";
  import OptionSelector from "@gallery/catalog/OptionSelector.svelte";

  let name = $state("");
  let textState = $state("empty");
  const textStates = ["empty", "filled", "error", "secure"] as const;

  let chatText = $state("");
  let micState = $state<MicState>("idle");
  let sendState = $state("send");
</script>

<div class="doc">
  <h2 class="t-titleM">Text input</h2>
  <div class="controls">
    <OptionSelector options={textStates} bind:value={textState} />
  </div>
  <div class="specimen">
    <div class="sizer">
      {#if textState === "empty"}
        <TextInput label="Fornavn *" bind:value={name} />
      {:else if textState === "filled"}
        <TextInput label="Fornavn *" value="Martin Hansen" />
      {:else if textState === "error"}
        <TextInput
          label="Fornavn *"
          value="A very long name that will definitely overflow"
          isError
          errorMessage="Det her er helt forkert."
        />
      {:else}
        <TextInput label="Adgangskode" value="ABC123" isSecure />
      {/if}
    </div>
  </div>

  <h2 class="t-titleM">Chat input</h2>
  <div class="controls">
    <OptionSelector options={["idle", "active"]} bind:value={micState as never} />
    <OptionSelector options={["send", "stop"]} bind:value={sendState} />
  </div>
  <div class="specimen">
    <div class="sizer">
      <ChatInput
        bind:value={chatText}
        isSendEnabled={chatText.trim().length > 0}
        showStopButton={sendState === "stop"}
        {micState}
        onSend={() => (chatText = "")}
        onMicTap={() => (micState = micState === "active" ? "idle" : "active")}
        onActionTap={() => {}}
      />
    </div>
  </div>
  <p class="hint">Focus the chat input to see it expand into a card with a footer row.</p>
</div>

<style>
  .controls {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n16);
    margin: var(--spacing-n16) 0 var(--spacing-n24);
  }

  .specimen {
    padding: var(--spacing-n24);
    margin-bottom: var(--spacing-n16);
    border-radius: var(--radius-card);
    background: var(--color-surface-standard-base);
    display: flex;
    justify-content: center;
  }

  /* Inputs stretch, so give them a comfortable specimen column. */
  .sizer {
    width: 100%;
    max-width: 480px;
  }

  .hint {
    color: var(--color-text-standard-muted);
    margin-bottom: var(--spacing-n40);
  }
</style>
