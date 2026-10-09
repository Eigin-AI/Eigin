<script lang="ts">
  import { ActionButton, Button, SegmentedControl } from "@lib";
  import { turnKinds, type Turn, type TurnKind } from "@gallery/showcase/conversation";

  let { turns = $bindable() }: { turns: Turn[] } = $props();

  const segments = turnKinds.map(({ id, label }) => ({ value: id, label }));
  const hint = (kind: TurnKind) => turnKinds.find((candidate) => candidate.id === kind)?.hint;

  function move(index: number, by: number) {
    const [turn] = turns.splice(index, 1);
    turns.splice(index + by, 0, turn);
  }

  /* A new turn answers the last one: you, then Eigin, then you again. */
  function add() {
    const last = turns.at(-1)?.kind;
    turns.push({ kind: last === "user" ? "agent" : "user", text: "" });
  }
</script>

<!-- The feed, top to bottom: each turn is a kind and its text. -->
<ol class="turns">
  {#each turns as turn, index (index)}
    <li class="turn">
      <SegmentedControl
        {segments}
        selection={turn.kind}
        onSelect={(next) => (turn.kind = next as TurnKind)}
      />
      <textarea
        class="showcase-textarea t-description"
        rows={turn.kind === "agent" ? 5 : 2}
        placeholder={hint(turn.kind)}
        bind:value={turn.text}
      ></textarea>
      <span class="turn-tools">
        <ActionButton
          icon="functional/arrow/up"
          variant="open"
          size="small"
          label="Move up"
          disabled={index === 0}
          onclick={() => move(index, -1)}
        />
        <ActionButton
          icon="functional/arrow/down"
          variant="open"
          size="small"
          label="Move down"
          disabled={index === turns.length - 1}
          onclick={() => move(index, 1)}
        />
        <ActionButton
          icon="functional/trash"
          variant="open"
          size="small"
          label="Remove"
          onclick={() => turns.splice(index, 1)}
        />
      </span>
    </li>
  {/each}
</ol>
<Button label="Add turn" variant="secondary" size="small" onclick={add} />

<style>
  .turns {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n12);
    margin: 0;
    padding: 0;
    list-style: none;
    align-self: stretch;
  }

  .turn {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--spacing-n8);
  }

  /* Under the text, out of the tabs' way, at the trailing edge. */
  .turn-tools {
    display: flex;
    justify-content: flex-end;
    align-self: stretch;
    margin-top: calc(-1 * var(--spacing-n4));
  }
</style>
