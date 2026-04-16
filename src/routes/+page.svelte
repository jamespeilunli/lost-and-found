<script lang="ts">
  import { onMount } from "svelte";
  import { Sun, Moon, Plus, Tag, MapPin, CalendarDays } from "lucide-svelte";
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
  let deletedItems: ItemRow[] = [];
  let viewingDeleted = false;
  $: isLibrarian = userRole === "librarian";

  // computed list to render (either normal items or deleted items)
  $: displayedItems = viewingDeleted ? deletedItems : items;

  let isDark = false;

  function statusBadgeVariant(status: ItemStatus) {
    if (status === "found") {
      return "bg-emerald-100 text-emerald-900 uppercase dark:bg-emerald-950 dark:text-emerald-300";
    }

    if (status === "claimed") {
      return "bg-sky-100 text-sky-900 uppercase dark:bg-sky-950 dark:text-sky-300";
    }

    return "bg-primary/20 text-foreground uppercase dark:bg-primary/25";
  }

  function formatItemDate(value: string) {
    return new Date(value).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
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

  async function setViewingDeleted(nextValue: boolean) {
    viewingDeleted = nextValue;

    if (viewingDeleted) {
      await loadDeletedItems();
      return;
    }

    await loadItems();
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

    // Choose which table to read from based on the tab
    const currentTable = viewingDeleted ? "deleted_items" : "items";

    const { data, error } = await supabase.from(currentTable).select("*").order("created_at", { ascending: false });

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

  async function loadDeletedItems() {
    itemsLoading = true;
    itemsError = "";

    const { data, error } = await supabase.from("deleted_items").select("*").order("created_at", { ascending: false });

    if (error) {
      itemsError = error.message;
      deletedItems = [];
    } else {
      deletedItems = (data ?? []) as ItemRow[];
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
      toast.error("Could not update item status: " + error.message);
      return;
    }

    items = items.map((item) => (item.id === itemId ? (data as ItemRow) : item));
    toast.success(`Item marked as ${nextStatus}.`);
  }

  async function deleteItem(itemId: string) {
    const item = items.find((i) => i.id === itemId);
    const isOwner = session?.user?.id === item?.created_by;

    if (!isLibrarian && !isOwner) {
      return;
    }
    // Try to archive the item into `deleted_items` first so we keep a record.
    try {
      const toInsert = {
        // copy all known item fields; keep id so deleted_items mirrors items
        id: item?.id,
        title: item?.title,
        description: item?.description,
        category: item?.category,
        status: item?.status,
        image_url: item?.image_url,
        location_found: item?.location_found,
        created_at: item?.created_at,
        created_by: item?.created_by,
      };

      const { data: insertData, error: insertError } = await supabase.from("deleted_items").insert([toInsert]).select();

      if (insertError) {
        itemsError = insertError.message;
        toast.error("Failed to archive deleted item: " + insertError.message);
        return;
      }

      // Now delete from the original table
      const { data, error } = await supabase.from("items").delete().eq("id", itemId).select();

      if (error) {
        itemsError = error.message;
        toast.error("Deleted item was archived but removing the original failed: " + error.message);
        return;
      }

      if (!data || data.length === 0) {
        alert("Failed to delete item. You may lack permission, or Row Level Security (RLS) is blocking the action.");
        return;
      }

      // Update local state
      items = items.filter((item) => item.id !== itemId);
      // If we're viewing deleted items, reload that list so the new row appears
      if (viewingDeleted) {
        await loadDeletedItems();
      }

      toast.success("Item deleted and archived successfully.");
    } catch (err) {
      itemsError = (err as Error).message;
      toast.error("An unexpected error occurred: " + (err as Error).message);
    }
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
  <title>Library Lost & Found</title>
  <meta name="description" content="Browse and manage library lost and found records." />
</svelte:head>

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-6xl px-4 py-4 md:py-5">
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div class="text-left">
          <h1 class="text-left text-2xl font-bold leading-tight md:text-3xl">Library Lost &amp; Found</h1>
          <p class="mt-1 max-w-2xl text-sm text-muted-foreground">
            Browse recently reported items, check their status, and submit a report if you recognize something.
          </p>
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
              <Badge variant="outline" class="w-fit border-primary/40 text-sm uppercase tracking-wide">
                {userRole ?? "unknown"}
              </Badge>
              <Button variant="outline" class="text-sm" onclick={handleLogout} disabled={authLoading}>Log out</Button>
            </div>
          {:else}
            <Button class="w-full text-sm sm:w-auto" onclick={handleGoogleSignIn} disabled={authLoading}>
              {authLoading ? "Redirecting..." : "Sign in to report an item"}
            </Button>
          {/if}
        </div>
      </div>

      {#if authError}
        <Alert variant="destructive" class="mt-4 text-sm">
          <AlertTitle>Authentication error</AlertTitle>
          <AlertDescription>{authError}</AlertDescription>
        </Alert>
      {/if}
    </div>
  </header>

  <main class="mx-auto max-w-6xl px-4 py-6">
    {#if isLibrarian}
      <Alert class="mb-6 border-primary/40 bg-primary/10 text-sm">
        <AlertTitle>Librarian View</AlertTitle>
        <AlertDescription>
          You can update item statuses, review archived records, and remove reports from the public list.
        </AlertDescription>
      </Alert>
    {/if}

    <Card class="border-border/80 bg-card text-sm shadow-none">
      <CardHeader class="gap-3">
        <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <CardTitle class="text-xl md:text-2xl">
            {viewingDeleted ? "Archived records" : "Browse reported items"}
          </CardTitle>
          <div class="flex items-center gap-4">
            {#if session}
              <Button href="/submit" class="gap-1.5 text-sm">
                <Plus size={16} />
                <span>Report an item</span>
              </Button>
            {:else}
              <Button variant="secondary" class="gap-1.5 text-sm" disabled>
                <Plus size={16} />
                <span>Sign in to report</span>
              </Button>
            {/if}
            <Button variant="ghost" class="text-sm" onclick={loadItems} disabled={itemsLoading}>Refresh</Button>

            {#if isLibrarian}
              <div class="flex items-center overflow-hidden border border-border/80">
                <Button
                  variant={viewingDeleted ? "ghost" : "secondary"}
                  class="rounded-none border-0 text-sm"
                  onclick={() => setViewingDeleted(false)}
                  disabled={itemsLoading && !viewingDeleted}
                  aria-pressed={!viewingDeleted}
                >
                  Public list
                </Button>
                <Button
                  variant={viewingDeleted ? "secondary" : "ghost"}
                  class="rounded-none border-0 border-l border-border/80 text-sm"
                  onclick={() => setViewingDeleted(true)}
                  disabled={itemsLoading && viewingDeleted}
                  aria-pressed={viewingDeleted}
                >
                  Archived records
                </Button>
              </div>
            {/if}
          </div>
        </div>
        <CardDescription class="text-sm">
          {#if viewingDeleted}
            Archived records are visible to librarians only. Return to "Public list" to browse current reports.
          {:else}
            Signed-out visitors can browse everything here. Lost items stay prioritized, and your own submissions appear first when you sign in.
          {/if}
        </CardDescription>
      </CardHeader>
      <Separator class="bg-border/80" />
      <CardContent class="pb-5">
        {#if itemsLoading}
          <p class="text-muted-foreground">Loading items...</p>
        {:else if itemsError}
          <Alert variant="destructive" class="text-sm">
            <AlertTitle>Could not load items</AlertTitle>
            <AlertDescription>{itemsError}</AlertDescription>
          </Alert>
        {:else if displayedItems.length === 0}
          <p class="italic text-muted-foreground">No reports yet. Add the first item report.</p>
        {:else}
          <div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-3">
            {#each displayedItems as item (item.id)}
              {@const showItemActions =
                !viewingDeleted && (isLibrarian || (session && session.user.id === item.created_by))}
              <Card class="border-border/80 bg-card py-0">
                {#if item.image_url}
                  <img src={item.image_url} alt={item.title} class="h-44 w-full object-cover" />
                {:else}
                  <div class="flex h-44 w-full items-center justify-center bg-muted text-sm text-muted-foreground">
                    No image
                  </div>
                {/if}

                <CardContent class={`border-border/80 flex-1 space-y-4 ${showItemActions ? "" : "pb-4"}`}>
                  <div class="flex items-start justify-between">
                    <h3 class="text-base font-semibold md:text-lg">{item.title}</h3>
                    <Badge class={`${statusBadgeVariant(item.status)} text-sm`}>
                      {item.status}
                    </Badge>
                  </div>
                  <p class="text-sm text-muted-foreground">
                    {item.description}
                  </p>
                  <div class="flex flex-wrap gap-2 text-sm text-muted-foreground">
                    <div
                      class="inline-flex max-w-full items-center gap-2 rounded-full bg-muted/55 px-2.5 py-1.5"
                      title={`Category: ${item.category}`}
                      aria-label={`Category: ${item.category}`}
                    >
                      <Tag size={15} class="shrink-0 text-primary" />
                      <span class="truncate">{item.category}</span>
                    </div>
                    {#if item.location_found}
                      <div
                        class="inline-flex max-w-full items-center gap-2 rounded-full bg-muted/55 px-2.5 py-1.5"
                        title={`Location: ${item.location_found}`}
                        aria-label={`Location: ${item.location_found}`}
                      >
                        <MapPin size={15} class="shrink-0 text-primary" />
                        <span class="truncate">{item.location_found}</span>
                      </div>
                    {/if}
                    <div
                      class="inline-flex max-w-full items-center gap-2 rounded-full bg-muted/55 px-2.5 py-1.5"
                      title={`Created: ${formatItemDate(item.created_at)}`}
                      aria-label={`Created: ${formatItemDate(item.created_at)}`}
                    >
                      <CalendarDays size={15} class="shrink-0 text-primary" />
                      <span>{formatItemDate(item.created_at)}</span>
                    </div>
                  </div>
                </CardContent>

                {#if showItemActions}
                  <CardFooter class="border-border/80 flex items-center justify-between gap-2 bg-card px-4 py-4">
                    <div class="flex flex-wrap items-center gap-2">
                      {#if isLibrarian}
                        <Select
                          type="single"
                          value={item.status}
                          onValueChange={(value: string) => updateItemStatus(item.id, value as ItemStatus)}
                        >
                          <SelectTrigger class="w-[140px] bg-background text-sm">
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
                        <Button href="/edit/{item.id}" variant="outline" size="sm" class="text-sm">Edit</Button>
                      {/if}
                    </div>
                    <Button
                      variant="destructive"
                      size="sm"
                      class="text-sm"
                      onclick={() => {
                        if (confirm("Archive and remove this item from the public list?")) {
                          deleteItem(item.id);
                        }
                      }}
                    >
                      {isLibrarian ? "Archive item" : "Delete"}
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
