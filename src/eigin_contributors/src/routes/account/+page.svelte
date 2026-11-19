<script lang="ts">
  let { data } = $props();
</script>

<svelte:head><title>Your account · Eigin</title></svelte:head>
<section class="container section">
  <div class="page-intro">
    <h1 class="t-display page-title">Your account</h1>
    <p class="t-standfirst intro">{data.user.name} · @{data.user.username}</p>
  </div>
  <p class="t-body spaced">
    Signed in through code.eigin.ai. GitLab user ID: {data.user.gitlabId}.
  </p>
  {#if data.canReview}<p class="t-body spaced">
      <a href="/review">Review submissions</a>
    </p>{/if}
  <p class="t-body spaced">
    <a href="/#open-calls">Browse open calls</a>
  </p>
</section>
