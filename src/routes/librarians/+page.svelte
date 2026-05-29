<script lang="ts">
  import { onMount } from "svelte";
  import { ArrowLeft, MailPlus, Search, ShieldCheck, Trash2 } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Badge } from "$lib/components/ui/badge";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "$lib/components/ui/card";
  import { Input } from "$lib/components/ui/input";
  import { Label } from "$lib/components/ui/label";
  import { Separator } from "$lib/components/ui/separator";

  type LibrarianEmailRow = {
    email: string;
    created_at: string;
    created_by: string | null;
  };

  let session: Session | null = null;
  let isLibrarian = false;
  let authChecked = false;

  let emails: LibrarianEmailRow[] = [];
  let loading = false;
  let loadError = "";
  let search = "";
  let newEmail = "";
  let pendingEmail: string | null = null;

  $: currentEmail = session?.user.email?.toLowerCase() ?? "";
  $: filtered = emails.filter((row) => {
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return row.email.toLowerCase().includes(q);
  });

  function formatDate(value: string) {
    return new Date(value).toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  }

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;

    if (!session) {
      isLibrarian = false;
      authChecked = true;
      return;
    }

    const { data: allowed } = await supabase.rpc("is_librarian_email");
    isLibrarian = allowed === true;
    authChecked = true;

    if (!isLibrarian) {
      await supabase.auth.signOut();
    }
  }

  async function loadEmails() {
    loading = true;
    loadError = "";

    const { data, error } = await supabase.rpc("list_librarian_emails");

    if (error) {
      loadError = error.message;
      emails = [];
    } else {
      emails = (data ?? []) as LibrarianEmailRow[];
    }

    loading = false;
  }

  async function addEmail() {
    const email = newEmail.trim().toLowerCase();
    if (!email) return;

    pendingEmail = email;
    const { data, error } = await supabase.rpc("add_librarian_email", {
      new_email: email,
    });
    pendingEmail = null;

    if (error) {
      toast.error(`Could not add email: ${error.message}`);
      return;
    }

    const addedRows = (data ?? []) as LibrarianEmailRow[];
    if (addedRows[0] && !emails.some((row) => row.email === addedRows[0].email)) {
      emails = [...emails, addedRows[0]].sort((a, b) => a.email.localeCompare(b.email));
    }
    newEmail = "";
    toast.success("Librarian email added.");
  }

  async function removeEmail(email: string) {
    if (email === currentEmail) {
      toast.error("You can't remove your own librarian email.");
      return;
    }

    pendingEmail = email;
    const { error } = await supabase.rpc("remove_librarian_email", {
      target_email: email,
    });
    pendingEmail = null;

    if (error) {
      toast.error(`Could not remove email: ${error.message}`);
      return;
    }

    emails = emails.filter((row) => row.email !== email);
    toast.success("Librarian email removed.");
  }

  onMount(async () => {
    await loadSession();
    if (isLibrarian) {
      await loadEmails();
    }
  });
</script>

<svelte:head>
  <title>Librarian whitelist</title>
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
          <h1 class="mt-2 text-2xl font-bold leading-tight md:text-3xl">Librarian whitelist</h1>
          <p class="mt-1 text-sm text-muted-foreground">
            Add the Google account emails that can manage inventory.
          </p>
        </div>
      </div>
    </div>
  </header>

  <main class="mx-auto max-w-4xl px-4 py-6">
    {#if !authChecked}
      <p class="text-muted-foreground">Loading...</p>
    {:else if !session}
      <Alert variant="destructive" class="text-sm">
        <AlertTitle>Sign in required</AlertTitle>
        <AlertDescription>You must be signed in as a whitelisted librarian.</AlertDescription>
      </Alert>
    {:else if !isLibrarian}
      <Alert variant="destructive" class="text-sm">
        <AlertTitle>Librarians only</AlertTitle>
        <AlertDescription>This account is not on the librarian whitelist.</AlertDescription>
      </Alert>
    {:else}
      <Card class="border-border/80 bg-card text-sm shadow-none">
        <CardHeader class="gap-4">
          <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <CardTitle class="text-xl md:text-2xl">Allowed emails</CardTitle>
              <CardDescription class="mt-1 text-sm">
                Whitelisted emails become librarian accounts after Google sign-in.
              </CardDescription>
            </div>
            <Button variant="ghost" class="w-fit text-sm" onclick={loadEmails} disabled={loading}>
              Refresh
            </Button>
          </div>

          <div class="grid gap-3 rounded-md border border-border/80 bg-background p-3 md:grid-cols-[1fr_auto] md:items-end">
            <div class="space-y-2">
              <Label class="text-sm" for="new-email-input">Email</Label>
              <Input
                id="new-email-input"
                type="email"
                placeholder="librarian@example.edu"
                bind:value={newEmail}
                onkeydown={(event: KeyboardEvent) => {
                  if (event.key === "Enter") addEmail();
                }}
              />
            </div>
            <Button class="gap-1.5 text-sm" onclick={addEmail} disabled={!newEmail.trim() || pendingEmail === newEmail.trim().toLowerCase()}>
              <MailPlus size={16} />
              <span>Add email</span>
            </Button>
          </div>

          <div class="relative">
            <Search size={16} class="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <Input type="search" placeholder="Search whitelist" bind:value={search} class="pl-9" />
          </div>
        </CardHeader>
        <Separator class="bg-border/80" />
        <CardContent class="pb-5">
          {#if loading}
            <p class="text-muted-foreground">Loading emails...</p>
          {:else if loadError}
            <Alert variant="destructive" class="text-sm">
              <AlertTitle>Could not load whitelist</AlertTitle>
              <AlertDescription>{loadError}</AlertDescription>
            </Alert>
          {:else if filtered.length === 0}
            <p class="italic text-muted-foreground">No emails match.</p>
          {:else}
            <ul class="divide-y divide-border/80">
              {#each filtered as row (row.email)}
                <li class="flex flex-col gap-3 py-3 sm:flex-row sm:items-center sm:justify-between">
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="truncate text-sm font-medium">{row.email}</span>
                      <Badge variant="outline" class="gap-1 border-primary/40 text-xs uppercase tracking-wide">
                        <ShieldCheck size={12} />
                        librarian
                      </Badge>
                      {#if row.email === currentEmail}
                        <Badge class="bg-muted text-xs text-foreground">you</Badge>
                      {/if}
                    </div>
                    <p class="mt-1 text-xs text-muted-foreground">Added {formatDate(row.created_at)}</p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    class="w-fit gap-1.5 text-sm"
                    disabled={pendingEmail === row.email || row.email === currentEmail}
                    onclick={() => removeEmail(row.email)}
                  >
                    <Trash2 size={14} />
                    <span>Remove</span>
                  </Button>
                </li>
              {/each}
            </ul>
          {/if}
        </CardContent>
      </Card>
    {/if}
  </main>
</div>
