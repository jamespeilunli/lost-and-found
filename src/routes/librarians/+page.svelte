<script lang="ts">
  import { onMount } from "svelte";
  import { goto } from "$app/navigation";
  import { ArrowLeft, Search, ShieldCheck, ShieldOff } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Badge } from "$lib/components/ui/badge";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "$lib/components/ui/card";
  import { Input } from "$lib/components/ui/input";
  import { Separator } from "$lib/components/ui/separator";

  type UserRole = "user" | "librarian";

  type ProfileRow = {
    id: string;
    role: UserRole;
    email: string | null;
  };

  let session: Session | null = null;
  let userRole: UserRole | null = null;
  let authChecked = false;

  let profiles: ProfileRow[] = [];
  let loading = false;
  let loadError = "";
  let search = "";
  let pendingId: string | null = null;

  $: isLibrarian = userRole === "librarian";
  $: filtered = profiles.filter((p) => {
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return (p.email ?? "").toLowerCase().includes(q) || p.id.toLowerCase().includes(q);
  });

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;

    if (!session) {
      userRole = null;
      authChecked = true;
      return;
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", session.user.id)
      .maybeSingle();

    userRole = (profile?.role as UserRole | null) ?? "user";
    authChecked = true;
  }

  async function loadProfiles() {
    loading = true;
    loadError = "";

    const { data, error } = await supabase.rpc("list_profiles_with_email");

    if (error) {
      loadError = error.message;
      profiles = [];
    } else {
      profiles = (data ?? []) as ProfileRow[];
    }

    loading = false;
  }

  async function setRole(profile: ProfileRow, nextRole: UserRole) {
    if (!isLibrarian) return;
    if (profile.id === session?.user?.id && nextRole === "user") {
      toast.error("You can't demote yourself.");
      return;
    }

    pendingId = profile.id;

    const { error } = await supabase.rpc("set_profile_role", {
      target_id: profile.id,
      new_role: nextRole,
    });

    pendingId = null;

    if (error) {
      toast.error(`Could not update role: ${error.message}`);
      return;
    }

    profiles = profiles.map((p) => (p.id === profile.id ? { ...p, role: nextRole } : p));
    toast.success(
      nextRole === "librarian"
        ? `${profile.email ?? "User"} is now a librarian.`
        : `${profile.email ?? "User"} is no longer a librarian.`,
    );
  }

  onMount(async () => {
    await loadSession();
    if (userRole === "librarian") {
      await loadProfiles();
    }
  });
</script>

<svelte:head>
  <title>Manage librarians</title>
</svelte:head>

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-4xl px-4 py-4 md:py-5">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <h1 class="text-2xl font-bold leading-tight md:text-3xl">Manage librarians</h1>
          <p class="mt-1 text-sm text-muted-foreground">
            Promote users to librarians or remove librarian access.
          </p>
        </div>
        <Button variant="outline" class="gap-1.5 text-sm w-fit" onclick={() => goto("/")}>
          <ArrowLeft size={16} />
          <span>Back</span>
        </Button>
      </div>
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
    {:else if !isLibrarian}
      <Alert variant="destructive" class="text-sm">
        <AlertTitle>Librarians only</AlertTitle>
        <AlertDescription>You need librarian access to view this page.</AlertDescription>
      </Alert>
    {:else}
      <Card class="border-border/80 bg-card text-sm shadow-none">
        <CardHeader class="gap-3">
          <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <CardTitle class="text-xl md:text-2xl">Users</CardTitle>
            <Button variant="ghost" class="text-sm w-fit" onclick={loadProfiles} disabled={loading}>
              Refresh
            </Button>
          </div>
          <CardDescription class="text-sm">
            Search by email, then promote or demote any account.
          </CardDescription>
          <div class="relative">
            <Search size={16} class="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <Input
              type="search"
              placeholder="Search by email"
              bind:value={search}
              class="pl-9"
            />
          </div>
        </CardHeader>
        <Separator class="bg-border/80" />
        <CardContent class="pb-5">
          {#if loading}
            <p class="text-muted-foreground">Loading users...</p>
          {:else if loadError}
            <Alert variant="destructive" class="text-sm">
              <AlertTitle>Could not load users</AlertTitle>
              <AlertDescription>{loadError}</AlertDescription>
            </Alert>
          {:else if filtered.length === 0}
            <p class="italic text-muted-foreground">No users match.</p>
          {:else}
            <ul class="divide-y divide-border/80">
              {#each filtered as profile (profile.id)}
                <li class="flex flex-col gap-3 py-3 sm:flex-row sm:items-center sm:justify-between">
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="truncate text-sm font-medium">
                        {profile.email ?? profile.id}
                      </span>
                      <Badge
                        variant="outline"
                        class="border-primary/40 text-xs uppercase tracking-wide"
                      >
                        {profile.role}
                      </Badge>
                      {#if profile.id === session.user.id}
                        <Badge class="bg-muted text-xs text-foreground">you</Badge>
                      {/if}
                    </div>
                    {#if profile.email}
                      <p class="truncate text-xs text-muted-foreground">{profile.id}</p>
                    {/if}
                  </div>
                  <div class="flex shrink-0 gap-2">
                    {#if profile.role === "librarian"}
                      <Button
                        variant="outline"
                        size="sm"
                        class="gap-1.5 text-sm"
                        disabled={pendingId === profile.id || profile.id === session.user.id}
                        onclick={() => setRole(profile, "user")}
                      >
                        <ShieldOff size={14} />
                        Remove librarian
                      </Button>
                    {:else}
                      <Button
                        size="sm"
                        class="gap-1.5 text-sm"
                        disabled={pendingId === profile.id}
                        onclick={() => setRole(profile, "librarian")}
                      >
                        <ShieldCheck size={14} />
                        Make librarian
                      </Button>
                    {/if}
                  </div>
                </li>
              {/each}
            </ul>
          {/if}
        </CardContent>
      </Card>
    {/if}
  </main>
</div>
