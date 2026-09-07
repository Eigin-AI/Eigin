<script lang="ts">
  import type { Snippet } from "svelte";
  import StatusLine from "./StatusLine.svelte";
  import Mark from "./Mark.svelte";
  import type { ConnectionState } from "./types";
  import type { IconName } from "../../generated/icons";

  const {
    name,
    kind,
    icon,
    emoji,
    letter,
    mark,
    state,
    status,
  }: {
    name: string;
    /** What sort of connection: "AI provider", "Email account", "MCP server".
        Omitted where the name and the status already say it. */
    kind?: string;
    icon?: IconName;
    emoji?: string;
    /** Stand-in mark for a connection with no logo: its own initial. */
    letter?: string;
    /** A mark of its own, in place of the standard circle. Eigin's is ours. */
    mark?: Snippet;
    state: ConnectionState;
    status: string;
  } = $props();
</script>

<!--
  The top of every connection screen: a mark, the name, what kind of thing it
  is, and whether it is working. The same block whether it is Anthropic, a
  Gmail account, an MCP server or the model on the phone.
-->
<header class="identity">
  {#if mark}
    {@render mark()}
  {:else}
    <Mark {icon} {emoji} {letter} size={64} />
  {/if}
  <div class="names">
    <h2 class="t-titleM name">{name}</h2>
    {#if kind}
      <span class="t-tag kind">{kind}</span>
    {/if}
    <StatusLine {state} label={status} />
  </div>
</header>

<style>
  .identity {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n16);
    padding: var(--spacing-n16) 0 var(--spacing-n8);
    text-align: center;
  }

  /* Name, kind and status are one block at one gap: the status sitting a step
     further out than the kind made the three lines read as two things.

     Typography here is trimmed to the cap height, so this is the space you
     see. n8 under a 30px display face read as a collision. */
  .names {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-n12);
  }

  .name {
    margin: 0;
    color: var(--color-text-standard-base);
  }

  .kind {
    color: var(--color-text-standard-muted);
  }
</style>
