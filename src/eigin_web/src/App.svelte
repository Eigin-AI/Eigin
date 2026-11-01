<script lang="ts">
  import { onMount } from "svelte";
  import { initialize } from "@eigin/sdk";

  let status = $state("Initializing Eigin SDK…");
  onMount(() => {
    initialize().then(
      () => { status = "Eigin SDK initialized"; },
      (error: unknown) => {
        status = `SDK initialization failed: ${error instanceof Error ? error.message : String(error)}`;
      },
    );
  });
</script>

<main>
  <h1>Eigin SDK test host</h1>
  <p>This page validates browser compatibility for the Eigin SDK. This test host will grow into the Eigin web application.</p>
  <p role="status">{status}</p>
</main>
