<script lang="ts">
	import { resolve } from '$app/paths';
	import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '$lib/components/ui/card';
	import { Separator } from '$lib/components/ui/separator';
</script>

<svelte:head>
	<title>About</title>
	<meta name="description" content="About this app" />
</svelte:head>

<div class="mx-auto max-w-3xl px-4 py-10">
	<Card class="border-border/80 bg-card text-sm shadow-none">
		<CardHeader>
			<CardTitle class="text-2xl">About this app</CardTitle>
			<CardDescription class="text-sm">Static content rendered with the same UI system as the rest of the frontend.</CardDescription>
		</CardHeader>
		<Separator class="bg-border/80" />
		<CardContent class="space-y-4 pt-6 text-sm text-muted-foreground">
			<p>
				This is a <a class="text-foreground underline underline-offset-4" href="https://svelte.dev/docs/kit">SvelteKit</a> app. You can make your own by typing the following into your command line and following the prompts:
			</p>
			<pre class="border bg-muted px-3 py-2 text-foreground">npx sv create</pre>
			<p>
				The page you&apos;re looking at is purely static HTML, with no client-side interactivity needed. Because of that, we don&apos;t need to load any JavaScript.
			</p>
			<p>
				The rest of the app demonstrates the interactive flows: authentication, item submission, editing, and librarian updates.
			</p>
		</CardContent>
	</Card>
</div>
