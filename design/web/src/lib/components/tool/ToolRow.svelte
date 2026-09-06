<script lang="ts">
  import { statusSuffix, type ToolCall } from "./types";
  import "../../theme/pulse.css";

  interface Props {
    tool: ToolCall;
  }

  const { tool }: Props = $props();

  const suffix = $derived(statusSuffix(tool.status));
  const label = $derived(suffix ? `${tool.name} ${suffix}` : tool.name);
</script>

<span class="tool-row t-chatMessage {tool.status}" class:eigin-pulse={tool.status === "executing"}>
  {label}
</span>

<style>
  /* The n4 gutters assume untrimmed line boxes; trimming strips ~12px of
     leading, so the row carries it back to keep the iOS pitch (34pt). */
  .tool-row {
    display: block;
    padding: var(--spacing-n4) 0;
    margin-block: calc(var(--spacing-n12) / 2);
    color: var(--color-text-standard-muted);
    transition: color var(--motion-normal) var(--motion-easing-smooth);
  }

  /* A finished tool recedes; one waiting on the user asks for attention. */
  .tool-row.completed {
    opacity: 0.6;
  }

  .tool-row.awaitingPermission {
    color: var(--color-accent);
  }

  .tool-row.denied,
  .tool-row.error {
    color: var(--color-text-standard-error);
  }

  /* The breathe modifier is the pulse dipping deeper. */
  .tool-row {
    --pulse-depth: 0.4;
  }
</style>
