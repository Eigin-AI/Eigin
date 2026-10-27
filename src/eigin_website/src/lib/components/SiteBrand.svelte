<script lang="ts">
  import { Icon } from "@eigin/ui";
  let { href, label }: { href: string; label: string } = $props();
</script>

<a class="site-brand" {href} aria-label={label}>
  <span aria-hidden="true"><Icon name="brand/avatar" size={24} /></span>
  <span class="t-titleXS">Eigin</span>
</a>
