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
    return !q || row.email.toLowerCase().includes(q);
  });

  function formatDate(value: string) {
    return new Date(value).toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  }

  async function getAuthHeaders() {
    const { data } = await supabase.auth.getSession();
    const token = data.session?.access_token;
    if (!token) {
      throw new Error("Sign in required.");
    }

    return {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    };
  }

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    authChecked = true;
  }

  async function loadEmails() {
    if (!session) return;

    loading = true;
    loadError = "";

    try {
      const response = await fetch("/api/librarians", {
        headers: await getAuthHeaders(),
      });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(payload.message ?? "Could not load librarian emails.");
      }

      emails = (payload.emails ?? []) as LibrarianEmailRow[];
    } catch (error) {
      loadError = (error as Error).message;
      emails = [];
    } finally {
      loading = false;
    }
  }

  async function inviteEmail() {
    const email = newEmail.trim().toLowerCase();
    if (!email) return;

    pendingEmail = email;

    try {
      const response = await fetch("/api/librarians", {
        method: "POST",
        headers: await getAuthHeaders(),
        body: JSON.stringify({ email }),
      });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok && response.status !== 202) {
        throw new Error(payload.message ?? "Could not invite librarian.");
      }

      if (payload.email && !emails.some((row) => row.email === payload.email.email)) {
        emails = [...emails, payload.email].sort((a, b) => a.email.localeCompare(b.email));
      }

      newEmail = "";
      if (payload.warning) {
        toast.warning(payload.warning);
      } else {
        toast.success("Invite sent.");
      }
    } catch (error) {
      toast.error((error as Error).message);
    } finally {
      pendingEmail = null;
    }
  }

  async function removeEmail(email: string) {
    if (email === currentEmail) {
      toast.error("You can't remove your own librarian account.");
      return;
    }

    pendingEmail = email;

    try {
      const response = await fetch("/api/librarians", {
        method: "DELETE",
        headers: await getAuthHeaders(),
        body: JSON.stringify({ email }),
      });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok && response.status !== 202) {
        throw new Error(payload.message ?? "Could not remove librarian.");
      }

      emails = emails.filter((row) => row.email !== email);
      if (payload.warning) {
        toast.warning(payload.warning);
      } else {
        toast.success("Librarian removed.");
      }
    } catch (error) {
      toast.error((error as Error).message);
    } finally {
      pendingEmail = null;
    }
  }

  onMount(() => {
    void (async () => {
      await loadSession();
      await loadEmails();
    })();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      session = nextSession;
      authChecked = true;
      if (nextSession) {
        void loadEmails();
      } else {
        emails = [];
      }
    });

    return () => data.subscription.unsubscribe();
  });
</script>

<svelte:head>
  <title>Manage librarians</title>
</svelte:head>

<div class="min-h-screen bg-background text-foreground">
  <header class="border-b bg-card/95">
    <div class="mx-auto max-w-4xl px-4 py-5">
      <Button href="/" variant="outline" size="sm" class="gap-1 text-sm">
        <ArrowLeft size={18} />
        <span>Back</span>
      </Button>
      <h1 class="mt-3 text-2xl font-bold leading-tight md:text-3xl">Manage librarians</h1>
      <p class="mt-1 text-sm text-muted-foreground">Invite librarian accounts and remove access.</p>
    </div>
  </header>

  <main class="mx-auto max-w-4xl px-4 py-6">
    {#if !authChecked}
      <p class="text-muted-foreground">Loading...</p>
    {:else if !session}
      <Alert variant="destructive" class="text-sm">
        <AlertTitle>Sign in required</AlertTitle>
        <AlertDescription>You must be signed in to manage librarians.</AlertDescription>
      </Alert>
    {:else}
      <Card class="border-border/80 bg-card text-sm shadow-none">
        <CardHeader class="gap-4">
          <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <CardTitle class="text-xl md:text-2xl">Librarian accounts</CardTitle>
              <CardDescription class="mt-1 text-sm">
                Invited emails can set a password and sign in.
              </CardDescription>
            </div>
            <Button variant="ghost" class="w-fit text-sm" onclick={loadEmails} disabled={loading}>
              Refresh
            </Button>
          </div>

          <div class="grid gap-3 border border-border/80 bg-background p-3 md:grid-cols-[1fr_auto] md:items-end">
            <div class="space-y-2">
              <Label class="text-sm" for="new-email-input">Email</Label>
              <Input
                id="new-email-input"
                type="email"
                placeholder="librarian@example.edu"
                bind:value={newEmail}
                onkeydown={(event: KeyboardEvent) => {
                  if (event.key === "Enter") void inviteEmail();
                }}
              />
            </div>
            <Button class="gap-1.5 text-sm" onclick={inviteEmail} disabled={!newEmail.trim() || pendingEmail === newEmail.trim().toLowerCase()}>
              <MailPlus size={16} />
              <span>Invite</span>
            </Button>
          </div>

          <div class="relative">
            <Search size={16} class="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <Input type="search" placeholder="Search librarians" bind:value={search} class="pl-9" />
          </div>
        </CardHeader>
        <Separator class="bg-border/80" />
        <CardContent class="pb-5">
          {#if loading}
            <p class="text-muted-foreground">Loading emails...</p>
          {:else if loadError}
            <Alert variant="destructive" class="text-sm">
              <AlertTitle>Could not load librarians</AlertTitle>
              <AlertDescription>{loadError}</AlertDescription>
            </Alert>
          {:else if filtered.length === 0}
            <p class="italic text-muted-foreground">No emails match.</p>
          {:else}
            <ul class="divide-y divide-border/80">
              {#each filtered as row (row.email)}
                <li class="flex flex-col gap-3 py-3 sm:flex-row sm:items-center sm:justify-between">
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
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
