<script lang="ts">
  import { onMount } from "svelte";
  import { goto } from "$app/navigation";
  import { ArrowLeft, Mail } from "lucide-svelte";
  import { supabase } from "$lib/supabaseClient";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "$lib/components/ui/card";
  import { Input } from "$lib/components/ui/input";
  import { Label } from "$lib/components/ui/label";

  let email = "";
  let password = "";
  let mode: "signin" | "reset" = "signin";
  let loading = false;
  let errorMessage = "";
  let successMessage = "";

  async function handleSubmit() {
    loading = true;
    errorMessage = "";
    successMessage = "";

    if (mode === "reset") {
      const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
        redirectTo: `${window.location.origin}/set-password`,
      });

      loading = false;
      if (error) {
        errorMessage = error.message;
        return;
      }

      successMessage = "Check your email for a password reset link.";
      return;
    }

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    loading = false;
    if (error) {
      errorMessage = error.message;
      return;
    }

    await goto("/");
  }

  onMount(() => {
    void (async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) {
        await goto("/");
      }
    })();
  });
</script>

<svelte:head>
  <title>Librarian sign in | Lost and Found</title>
</svelte:head>

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-xl px-4 py-4 md:py-5">
      <Button href="/" variant="outline" size="sm" class="gap-1 text-sm">
        <ArrowLeft size={18} />
        <span>Back</span>
      </Button>
      <h1 class="mt-2 text-2xl font-bold leading-tight md:text-3xl">Librarian sign in</h1>
      <p class="mt-1 text-sm text-muted-foreground">Use your invited librarian account.</p>
    </div>
  </header>

  <main class="mx-auto max-w-xl px-4 py-6">
    <Card class="border-border/80 bg-card text-sm shadow-none">
      <form
        onsubmit={(event) => {
          event.preventDefault();
          void handleSubmit();
        }}
      >
        <CardHeader>
          <CardTitle class="flex items-center gap-2 text-xl">
            <Mail size={20} />
            {mode === "signin" ? "Sign in" : "Reset password"}
          </CardTitle>
          <CardDescription>
            {mode === "signin"
              ? "Librarian accounts are invite-only."
              : "We will email a secure password reset link."}
          </CardDescription>
        </CardHeader>
        <CardContent class="space-y-4 mt-4">
          {#if errorMessage}
            <Alert variant="destructive" class="text-sm">
              <AlertTitle>Authentication issue</AlertTitle>
              <AlertDescription>{errorMessage}</AlertDescription>
            </Alert>
          {/if}

          {#if successMessage}
            <Alert class="text-sm">
              <AlertTitle>Email sent</AlertTitle>
              <AlertDescription>{successMessage}</AlertDescription>
            </Alert>
          {/if}

          <div class="space-y-2">
            <Label for="email-input">Email</Label>
            <Input id="email-input" type="email" bind:value={email} autocomplete="email" />
          </div>

          {#if mode === "signin"}
            <div class="space-y-2">
              <Label for="password-input">Password</Label>
              <Input id="password-input" type="password" bind:value={password} autocomplete="current-password" />
            </div>
          {/if}
        </CardContent>
        <CardFooter class="flex flex-col items-stretch gap-3 border-t-0 sm:flex-row sm:items-center sm:justify-between">
          <button
            type="button"
            class="text-left text-sm text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
            onclick={() => {
              mode = mode === "signin" ? "reset" : "signin";
              errorMessage = "";
              successMessage = "";
            }}
          >
            {mode === "signin" ? "Forgot password?" : "Back to sign in"}
          </button>
          <Button type="submit" disabled={loading || !email.trim() || (mode === "signin" && !password)}>
            {loading ? "Working..." : mode === "signin" ? "Sign in" : "Send reset"}
          </Button>
        </CardFooter>
      </form>
    </Card>
  </main>
</div>
