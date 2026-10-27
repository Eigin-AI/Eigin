<script lang="ts">
  import type { Snippet } from "svelte";
  import { Icon } from "@eigin/ui";

  /** A native disclosure that slides open and closed; it still works without JavaScript. */
  let { summary, children }: { summary: string; children: Snippet } = $props();
  let details: HTMLDetailsElement;
  let content: HTMLDivElement;
  let expanded: boolean | undefined = $state();
  let animation: Animation | undefined;

  function toggle(event: MouseEvent) {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      expanded = !details.open;
      return;
    }
    event.preventDefault();
    expanded = !(expanded ?? details.open);
    const from = details.open ? content.getBoundingClientRect().height : 0;
    animation?.cancel();
    details.open = true;
    const to = expanded ? content.scrollHeight : 0;
    animation = content.animate(
      { height: [`${from}px`, `${to}px`], opacity: expanded ? [0, 1] : [1, 0] },
      { duration: 240, easing: "cubic-bezier(0.2, 0, 0, 1)" },
    );
    animation.onfinish = () => {
      details.open = Boolean(expanded);
      animation = undefined;
    };
  }
</script>

<details class="trust-more" data-expanded={expanded} bind:this={details}>
  <summary class="t-titleXS" onclick={toggle}>
    {summary}<span class="trust-more-icon" aria-hidden="true"
      ><Icon name="functional/chevron/down" size={16} /></span
    >
  </summary>
  <div class="trust-more-content" bind:this={content}>
    <div class="trust-more-inner">{@render children()}</div>
  </div>
</details>
