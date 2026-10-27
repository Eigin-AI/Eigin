<script lang="ts">
  import DocumentPage from "#lib/components/DocumentPage.svelte";
  import type { PageData } from "./$types";

  let { data }: { data: PageData } = $props();
</script>

<DocumentPage {...data} />
