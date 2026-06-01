<script lang="ts">
  import { onMount } from "svelte";
  import { goto } from "$app/navigation";
  import { ArrowLeft, KeyRound } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "$lib/components/ui/card";
  import { Input } from "$lib/components/ui/input";
  import { Label } from "$lib/components/ui/label";

  let session: Session | null = null;
  let checkedSession = false;
  let password = "";
  let confirmPassword = "";
  let errorMessage = "";
  let successMessage = "";
  let loading = false;

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    checkedSession = true;
  }

  async function handleSubmit() {
    errorMessage = "";
    successMessage = "";

    if (!session) {
      errorMessage = "This password link is expired or invalid. Request a new invite or reset email.";
      return;
    }

    if (password.length < 8) {
      errorMessage = "Use at least 8 characters.";
      return;
    }

    if (password !== confirmPassword) {
      errorMessage = "Passwords do not match.";
      return;
    }

    loading = true;
    const { error } = await supabase.auth.updateUser({ password });
    loading = false;

    if (error) {
      errorMessage = error.message;
      return;
    }

    successMessage = "Password updated. Redirecting...";
    toast.success("Password updated.");
    setTimeout(() => {
      goto("/");
    }, 700);
  }

  onMount(() => {
    void loadSession();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      session = nextSession;
      checkedSession = true;
    });

    return () => data.subscription.unsubscribe();
  });
</script>

<svelte:head>
  <title>Set password | Lost and Found</title>
</svelte:head>

<div class="min-h-screen bg-background text-foreground">
  <header class="border-b bg-card/95">
    <div class="mx-auto max-w-xl px-4 py-5">
      <Button href="/" variant="outline" size="sm" class="gap-1 text-sm">
        <ArrowLeft size={18} />
        <span>Back</span>
      </Button>
      <h1 class="mt-3 text-2xl font-bold leading-tight md:text-3xl">Set password</h1>
      <p class="mt-1 text-sm text-muted-foreground">Create a password for librarian sign-in.</p>
    </div>
  </header>

  <main class="mx-auto max-w-xl px-4 py-6">
    <Card class="border-border/80 bg-card shadow-none">
      <CardHeader>
        <CardTitle class="flex items-center gap-2 text-xl">
          <KeyRound size={20} />
          Password
        </CardTitle>
      </CardHeader>
      <CardContent class="space-y-4">
        {#if !checkedSession}
          <p class="text-sm text-muted-foreground">Checking link...</p>
        {:else if !session}
          <Alert variant="destructive" class="text-sm">
            <AlertTitle>Invalid link</AlertTitle>
            <AlertDescription>Request a new invite or password reset email.</AlertDescription>
          </Alert>
        {:else}
          {#if errorMessage}
            <Alert variant="destructive" class="text-sm">
              <AlertTitle>Could not update password</AlertTitle>
              <AlertDescription>{errorMessage}</AlertDescription>
            </Alert>
          {/if}

          {#if successMessage}
            <Alert class="text-sm">
              <AlertTitle>Password saved</AlertTitle>
              <AlertDescription>{successMessage}</AlertDescription>
            </Alert>
          {/if}

          <div class="space-y-2">
            <Label for="password-input">New password</Label>
            <Input id="password-input" type="password" bind:value={password} autocomplete="new-password" />
          </div>

          <div class="space-y-2">
            <Label for="confirm-password-input">Confirm password</Label>
            <Input
              id="confirm-password-input"
              type="password"
              bind:value={confirmPassword}
              autocomplete="new-password"
              onkeydown={(event: KeyboardEvent) => {
                if (event.key === "Enter") void handleSubmit();
              }}
            />
          </div>
        {/if}
      </CardContent>
      <CardFooter class="justify-end">
        <Button onclick={handleSubmit} disabled={!session || loading}>
          {loading ? "Saving..." : "Save password"}
        </Button>
      </CardFooter>
    </Card>
  </main>
</div>
