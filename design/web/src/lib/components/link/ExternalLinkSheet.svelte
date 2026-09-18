<script lang="ts">
  import Button from "../button/Button.svelte";
  import Sheet from "../sheet/Sheet.svelte";
  import { linkHost } from "./types";

  interface Props {
    /** Two-way bindable presentation state. */
    open?: boolean;
    href: string;
    onOpenLink?: (href: string) => void;
  }

  let { open = $bindable(false), href, onOpenLink }: Props = $props();

  /* The whole link where there is no host to shorten to. */
  const host = $derived(linkHost(href) || href);
</script>

<!--
  The check before a link leaves Eigin.

  The model chose the link, not you. So the host is named plainly, without the
  scheme and path to read past, and leaving is a second, deliberate tap.
-->
<Sheet
  bind:open
  title="Leave Eigin?"
  description="This opens {host} in your browser."
  showsDismissButton={false}
>
  {#snippet primary()}
    <div class="choices">
      <Button
        label="Open link"
        onclick={() => {
          open = false;
          onOpenLink?.(href);
        }}
      />
      <Button label="Stay here" variant="secondary" onclick={() => (open = false)} />
    </div>
  {/snippet}
</Sheet>

<style>
  .choices {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-n8);
    padding: 0 var(--sizing-pageLayout-contentGrouping-px-mobile);
  }
</style>
