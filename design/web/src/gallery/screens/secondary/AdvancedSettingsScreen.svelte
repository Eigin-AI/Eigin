<script lang="ts">
  import { ContentGroup, OptionPicker, Row, Switch } from "@lib";
  import SecondaryScreen from "./SecondaryScreen.svelte";
  let logging = $state(false);
  let level = $state("info");
  let message = $state("");
</script>

<SecondaryScreen title="Advanced" back="settings">
  <ContentGroup label="Storage"
    ><Row
      title="Local assets"
      description="Manage the models and voices stored on this device"
      onclick={() => (message = "Local asset management is outside this preview.")}
    /></ContentGroup
  >
  <ContentGroup
    label="Logging"
    footnote="Enables file-based logging for diagnostics. Log files can be exported and shared."
  >
    <Row title="Log to file" accessory="none"
      >{#snippet trailing()}<Switch
          label="Log to file"
          isOn={logging}
          onclick={() => (logging = !logging)}
        />{/snippet}</Row
    >
    {#if logging}
      <OptionPicker
        title="Minimum level"
        options={[
          { value: "debug", label: "Debug" },
          { value: "info", label: "Info" },
          { value: "warning", label: "Warning" },
          { value: "error", label: "Error" },
        ]}
        selection={level}
        onSelect={(value) => (level = value)}
      />
      <Row
        title="Export log"
        accessory="link"
        onclick={() => (message = "Preview only — no device logs are collected.")}
      />
      <Row
        title="Clear log"
        accessory="trash"
        tone="destructive"
        onclick={() => (message = "Sample log cleared.")}
      />
    {/if}
  </ContentGroup>
  {#if message}<p class="t-note" role="status">{message}</p>{/if}
</SecondaryScreen>
