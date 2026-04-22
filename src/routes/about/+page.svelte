<svelte:head>
  <title>About | Lost & Found</title>
  <meta
    name="description"
    content="Learn how Lost & Found helps students and librarians keep track of recovered items."
  />
</svelte:head>

<script lang="ts">
  const highlights = [
    "Report lost items with enough detail for quick matching.",
    "Track found items and where they were recovered.",
    "Give librarians a cleaner workflow for reunions and claims.",
  ];
</script>

<section class="min-h-screen bg-background px-6 py-16 text-foreground">
  <div class="mx-auto flex w-full max-w-4xl flex-col gap-8">
    <div class="space-y-4">
      <p class="text-sm font-semibold uppercase tracking-[0.3em] text-muted-foreground">About</p>
      <h1 class="max-w-2xl text-4xl font-semibold tracking-tight sm:text-5xl">
        A campus lost and found board built to reduce friction.
      </h1>
      <p class="max-w-2xl text-base leading-7 text-muted-foreground sm:text-lg">
        Lost &amp; Found gives students one place to log missing belongings and helps staff organize
        recovered items before they disappear into ad hoc spreadsheets or inbox threads.
      </p>
    </div>

    <div class="grid gap-4 sm:grid-cols-3">
      {#each highlights as highlight}
        <article class="border border-border bg-card p-5">
          <p class="text-sm leading-6 text-card-foreground">{highlight}</p>
        </article>
      {/each}
    </div>

    <div class="border border-border bg-card p-6">
      <h2 class="text-lg font-semibold">What this page does</h2>
      <p class="mt-3 max-w-2xl text-sm leading-6 text-muted-foreground">
        This route is static and prerenderable, so production builds can generate it without
        relying on runtime data.
      </p>
    </div>
  </div>
</section>
