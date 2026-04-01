<script lang="ts">
  import { onMount } from "svelte";
  import { Sun, Moon, Plus } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Badge } from "$lib/components/ui/badge";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "$lib/components/ui/card";
  import { Select, SelectContent, SelectItem, SelectTrigger } from "$lib/components/ui/select";
  import { Separator } from "$lib/components/ui/separator";

  type ItemStatus = "lost" | "found" | "claimed";
  type UserRole = "user" | "librarian";

  type ItemRow = {
    id: string;
    title: string;
    description: string;
    category: string;
    status: ItemStatus;
    image_url: string | null;
    location_found: string | null;
    created_at: string;
    created_by: string;
  };

  const statusOptions: ItemStatus[] = ["lost", "found", "claimed"];

  let session: Session | null = null;
  let userRole: UserRole | null = null;
  let authLoading = false;
  let authError = "";

  let items: ItemRow[] = [];
  let itemsLoading = false;
  let itemsError = "";
  $: isLibrarian = userRole === "librarian";

  let isDark = false;

  function statusBadgeVariant(status: ItemStatus) {
    if (status === "found") {
      return "bg-emerald-100 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-300";
    }

    if (status === "claimed") {
      return "bg-sky-100 text-sky-900 dark:bg-sky-950 dark:text-sky-300";
    }

    return "bg-primary/20 text-foreground dark:bg-primary/25";
  }

  function toggleTheme() {
    isDark = !isDark;
    if (isDark) {
      document.documentElement.classList.add("dark");
      localStorage.setItem("theme", "dark");
    } else {
      document.documentElement.classList.remove("dark");
      localStorage.setItem("theme", "light");
    }
  }

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    await loadUserRole(data.session?.user.id);
  }

  async function loadUserRole(userId?: string) {
    if (!userId) {
      userRole = null;
      return;
    }

    const { data, error } = await supabase.from("profiles").select("role").eq("id", userId).maybeSingle();

    if (error) {
      userRole = null;
      return;
    }

    userRole = (data?.role as UserRole | null) ?? "user";
  }

  async function loadItems() {
    itemsLoading = true;
    itemsError = "";

    const { data, error } = await supabase.from("items").select("*").order("created_at", { ascending: false });

    if (error) {
      itemsError = error.message;
      items = [];
    } else {
      let fetchedItems = data as ItemRow[];

      // Sort logic:
      // 1. User's own items first
      // 2. Lost items
      // 3. Other items (found/claimed)
      // 4. Fallback to created_at (already sorted by Supabase)
      const currentUserId = session?.user?.id;

      fetchedItems.sort((a, b) => {
        const aIsOwner = a.created_by === currentUserId;
        const bIsOwner = b.created_by === currentUserId;

        // 1. Prioritize user's own items
        if (aIsOwner && !bIsOwner) return -1;
        if (!aIsOwner && bIsOwner) return 1;

        // 2. Prioritize "lost" status
        const aIsLost = a.status === "lost";
        const bIsLost = b.status === "lost";

        if (aIsLost && !bIsLost) return -1;
        if (!aIsLost && bIsLost) return 1;

        // Maintain created_at order if all else is equal
        return 0;
      });

      items = fetchedItems;
    }

    itemsLoading = false;
  }

  async function handleGoogleSignIn() {
    authLoading = true;
    authError = "";

    const redirectTo = typeof window !== "undefined" ? `${window.location.origin}` : undefined;
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo },
    });

    if (error) {
      authError = error.message;
    }

    authLoading = false;
  }

  async function handleLogout() {
    authLoading = true;
    authError = "";

    const { error } = await supabase.auth.signOut();
    if (error) {
      authError = error.message;
    }

    authLoading = false;
  }

  async function updateItemStatus(itemId: string, nextStatus: ItemStatus) {
    if (!isLibrarian) {
      return;
    }

    const { data, error } = await supabase
      .from("items")
      .update({ status: nextStatus })
      .eq("id", itemId)
      .select()
      .single();

    if (error) {
      itemsError = error.message;
      return;
    }

    items = items.map((item) => (item.id === itemId ? (data as ItemRow) : item));
  }

  async function deleteItem(itemId: string) {
    const item = items.find((i) => i.id === itemId);
    const isOwner = session?.user?.id === item?.created_by;

    if (!isLibrarian && !isOwner) {
      return;
    }

    const { data, error } = await supabase.from("items").delete().eq("id", itemId).select();

    if (error) {
      itemsError = error.message;
      return;
    }

    if (!data || data.length === 0) {
      alert("Failed to delete item. You may lack permission, or Row Level Security (RLS) is blocking the action.");
      return;
    }

    items = items.filter((item) => item.id !== itemId);
    toast.success("Item deleted successfully.");
  }

  onMount(() => {
    isDark = document.documentElement.classList.contains("dark");

    loadSession();
    loadItems();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      session = nextSession;
      loadUserRole(nextSession?.user.id);
      loadItems();
    });

    return () => {
      data.subscription.unsubscribe();
    };
  });
</script>

<svelte:head>
  <title>Lost and Found</title>
  <meta name="description" content="Track lost-and-found entries" />
</svelte:head>

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-6xl px-4 py-4 md:py-5">
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div class="text-left">
          <h1 class="text-left text-2xl font-bold leading-tight md:text-3xl">Lost and Found</h1>
          <p class="mt-1 text-sm text-muted-foreground">Add, track, and update community lost-and-found items.</p>
        </div>

        <div class="flex items-center gap-3">
          <Button
            variant="outline"
            size="icon"
            class="bg-background"
            onclick={toggleTheme}
            aria-label="Toggle dark mode"
          >
            {#if isDark}
              <Sun size={20} />
            {:else}
              <Moon size={20} />
            {/if}
          </Button>

          {#if session}
            <div class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4 md:justify-end">
              <div class="text-sm text-muted-foreground">
                Signed in as <strong>{session.user.email}</strong>
              </div>
              <Badge variant="outline" class="w-fit border-primary/40 uppercase tracking-wide">
                {userRole ?? "unknown"}
              </Badge>
              <Button variant="outline" onclick={handleLogout} disabled={authLoading}>Log out</Button>
            </div>
          {:else}
            <Button class="w-full sm:w-auto" onclick={handleGoogleSignIn} disabled={authLoading}>
              {authLoading ? "Redirecting..." : "Continue with Google"}
            </Button>
          {/if}
        </div>
      </div>

      {#if authError}
        <Alert variant="destructive" class="mt-4">
          <AlertTitle>Authentication error</AlertTitle>
          <AlertDescription>{authError}</AlertDescription>
        </Alert>
      {/if}
    </div>
  </header>

  <main class="mx-auto max-w-6xl px-4 py-6">
    <Card class="border-border/80 bg-card shadow-none">
      <CardHeader class="gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <CardTitle class="text-xl md:text-2xl">Items</CardTitle>
          <CardDescription>Lost items stay prioritized, and your own submissions appear first.</CardDescription>
        </div>
        <div class="flex items-center gap-4">
          {#if session}
            <Button href="/submit" class="gap-1.5">
              <Plus size={16} />
              <span>Add item</span>
            </Button>
          {:else}
            <Button variant="secondary" class="gap-1.5" disabled>
              <Plus size={16} />
              <span>Add item</span>
            </Button>
          {/if}
          <Button variant="ghost" onclick={loadItems} disabled={itemsLoading}>Refresh</Button>
        </div>
      </CardHeader>
      <Separator />
      <CardContent class="pb-5">
        {#if itemsLoading}
          <p class="text-muted-foreground">Loading items...</p>
        {:else if itemsError}
          <Alert variant="destructive">
            <AlertTitle>Could not load items</AlertTitle>
            <AlertDescription>{itemsError}</AlertDescription>
          </Alert>
        {:else if items.length === 0}
          <p class="italic text-muted-foreground">No items yet. Add the first item.</p>
        {:else}
          <div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-3">
            {#each items as item (item.id)}
              <Card class="border-border/80 bg-card py-0">
                {#if item.image_url}
                  <img src={item.image_url} alt={item.title} class="h-44 w-full object-cover" />
                {:else}
                  <div class="flex h-44 w-full items-center justify-center bg-muted text-sm text-muted-foreground">
                    No image
                  </div>
                {/if}

                <CardContent class="flex-1 space-y-2">
                  <div class="flex items-start justify-between">
                    <h3 class="text-base font-semibold md:text-lg">{item.title}</h3>
                    <Badge class={statusBadgeVariant(item.status)}>
                      {item.status}
                    </Badge>
                  </div>
                  <p class="text-sm text-muted-foreground">
                    {item.description}
                  </p>
                  <div class="space-y-1 text-xs text-muted-foreground">
                    <div>Category: {item.category}</div>
                    {#if item.location_found}
                      <div>Location: {item.location_found}</div>
                    {/if}
                    <div>
                      Created: {new Date(item.created_at).toLocaleString()}
                    </div>
                  </div>
                </CardContent>

                {#if isLibrarian || (session && session.user.id === item.created_by)}
                  <CardFooter class="flex items-center justify-between gap-2 bg-card px-4 py-4">
                    <div class="flex flex-wrap items-center gap-2">
                      {#if isLibrarian}
                        <Select
                          type="single"
                          value={item.status}
                          onValueChange={(value: string) => updateItemStatus(item.id, value as ItemStatus)}
                        >
                          <SelectTrigger class="w-[140px] bg-background">
                            {item.status}
                          </SelectTrigger>
                          <SelectContent>
                            {#each statusOptions as option}
                              <SelectItem value={option} label={option} />
                            {/each}
                          </SelectContent>
                        </Select>
                      {/if}
                      {#if session && session.user.id === item.created_by}
                        <Button href="/edit/{item.id}" variant="outline" size="sm">Edit</Button>
                      {/if}
                    </div>
                    <Button
                      variant="destructive"
                      size="sm"
                      onclick={() => {
                        if (confirm("Are you sure you want to delete this item?")) {
                          deleteItem(item.id);
                        }
                      }}
                    >
                      Delete
                    </Button>
                  </CardFooter>
                {/if}
              </Card>
            {/each}
          </div>
        {/if}
      </CardContent>
    </Card>
  </main>
</div>
