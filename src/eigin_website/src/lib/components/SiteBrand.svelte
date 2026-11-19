<script lang="ts">
  import { Icon } from "@eigin/ui";
  let {
    href,
    label,
    name = "Eigin",
  }: {
    href: string;
    label: string;
    /** Visible product name in the shared brand lockup. */
    name?: string;
  } = $props();
</script>

<a class="site-brand" {href} aria-label={label}>
  <span aria-hidden="true"><Icon name="brand/avatar" size={26} /></span>
  <span class="t-titleXS">{name}</span>
</a>
