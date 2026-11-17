<script lang="ts">
  import NewsPage from "#lib/components/NewsPage.svelte";
  import type { PageData } from "./$types";
  let { data }: { data: PageData } = $props();
</script>

<NewsPage {data} />
