<script lang="ts">
  import { ArrowLeft, ExternalLink } from "lucide-svelte";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "$lib/components/ui/card";
</script>

<svelte:head>
  <title>About | Library Inventory</title>
  <meta
    name="description"
    content="About the unofficial library inventory app."
  />
</svelte:head>

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-4xl px-4 py-4 md:py-5">
      <div class="flex flex-col gap-4">
        <div class="text-left">
          <Button href="/" variant="outline" size="sm" class="gap-1 text-sm">
            <ArrowLeft size={18} />
            <span>Back</span>
          </Button>
          <h1 class="mt-2 text-2xl font-bold leading-tight md:text-3xl">About</h1>
          <p class="mt-1 text-sm text-muted-foreground">
            A short overview of the unofficial inventory app.
          </p>
        </div>
      </div>
    </div>
  </header>

  <main class="mx-auto max-w-4xl px-4 py-6">
    <Card class="border-border/80 bg-card text-sm shadow-none">
      <CardHeader>
        <CardTitle>Library Inventory</CardTitle>
        <CardDescription class="text-sm">
          An unofficial public inventory for library lost-and-found items.
        </CardDescription>
      </CardHeader>
      <CardContent class="space-y-4">
        <p class="text-sm leading-6 text-muted-foreground">
          Anyone can browse active found items without signing in. Whitelisted librarians can log
          found items, update statuses, set pickup deadlines, and keep records organized in one place.
        </p>
        <p class="text-sm leading-6 text-muted-foreground">
          This project is independently maintained and is not an official school or district service.
        </p>
        <a
          href="https://github.com/jamespeilunli/lost-and-found"
          target="_blank"
          rel="noreferrer"
          class="inline-flex items-center gap-1 text-sm font-medium text-primary underline-offset-4 hover:underline"
        >
          <span>View on GitHub</span>
          <ExternalLink size={14} />
        </a>
      </CardContent>
    </Card>
  </main>
</div>
