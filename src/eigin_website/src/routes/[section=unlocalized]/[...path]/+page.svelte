<script lang="ts">
  import LanguagePage from "#lib/components/LanguagePage.svelte";
  import type { PageData } from "./$types";
  let { data }: { data: PageData } = $props();
</script>

<LanguagePage path={data.path} />
