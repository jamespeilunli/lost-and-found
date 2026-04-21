<script lang="ts">
  import { onMount } from "svelte";
  import { Sun, Moon, Plus, Tag, MapPin, CalendarDays, EllipsisVertical, LogOut, Users, Mail, Search } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Badge } from "$lib/components/ui/badge";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "$lib/components/ui/card";
  import { Input } from "$lib/components/ui/input";
  import { Select, SelectContent, SelectItem, SelectTrigger } from "$lib/components/ui/select";
  import { Separator } from "$lib/components/ui/separator";

  type ItemStatus = "lost" | "found" | "claimed";
  type UserRole = "user" | "librarian";
  type ViewMode = "cards" | "table";

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
  let submitterEmails: Record<string, string> = {};
  let searchQuery = "";
  let viewMode: ViewMode = "cards";
  let expandedTableDescriptions: Record<string, boolean> = {};
  let expandedCardDescriptions: Record<string, boolean> = {};
  $: isLibrarian = userRole === "librarian";

  // computed list to render (either normal items or deleted items)
  $: displayedItems = viewingDeleted ? deletedItems : items;
  $: filteredDisplayedItems = getFilteredItems(displayedItems, searchQuery);

  let isDark = false;
  let menuOpen = false;
  let menuContainer: HTMLDivElement;

  function toggleMenu() {
    menuOpen = !menuOpen;
  }

  function closeMenu() {
    menuOpen = false;
  }

  function handleWindowClick(event: MouseEvent) {
    if (!menuOpen) return;
    if (menuContainer && !menuContainer.contains(event.target as Node)) {
      closeMenu();
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === "Escape" && menuOpen) {
      closeMenu();
    }
  }

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

  function normalizeSearchValue(value: string | null | undefined) {
    return (value ?? "")
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  function scoreFuzzyMatch(queryToken: string, searchText: string) {
    if (!queryToken || !searchText) {
      return 0;
    }

    const directIndex = searchText.indexOf(queryToken);
    if (directIndex !== -1) {
      const startsWord = directIndex === 0 || searchText[directIndex - 1] === " ";
      return 140 - directIndex * 2 - (searchText.length - queryToken.length) + (startsWord ? 20 : 0);
    }

    let score = 0;
    let previousIndex = -1;
    let streak = 0;

    for (const character of queryToken) {
      const nextIndex = searchText.indexOf(character, previousIndex + 1);
      if (nextIndex === -1) {
        return 0;
      }

      const isConsecutive = nextIndex === previousIndex + 1;
      streak = isConsecutive ? streak + 1 : 0;
      score += 10 + streak * 8;

      if (nextIndex === 0 || searchText[nextIndex - 1] === " ") {
        score += 12;
      }

      if (previousIndex !== -1) {
        score -= Math.min(nextIndex - previousIndex - 1, 6);
      }

      previousIndex = nextIndex;
    }

    return Math.max(score - (searchText.length - queryToken.length), 1);
  }

  function getItemSearchScore(item: ItemRow, query: string) {
    const tokens = normalizeSearchValue(query).split(" ").filter(Boolean);
    if (tokens.length === 0) {
      return 1;
    }

    const searchableFields = [
      { value: item.title, weight: 5 },
      { value: item.category, weight: 3 },
      { value: item.location_found, weight: 3 },
      { value: item.description, weight: 2 },
      { value: item.status, weight: 1 },
    ].map(({ value, weight }) => ({
      text: normalizeSearchValue(value),
      weight,
    }));

    let totalScore = 0;

    for (const token of tokens) {
      let bestScore = 0;

      for (const field of searchableFields) {
        const score = scoreFuzzyMatch(token, field.text) * field.weight;
        if (score > bestScore) {
          bestScore = score;
        }
      }

      if (bestScore === 0) {
        return 0;
      }

      totalScore += bestScore;
    }

    return totalScore;
  }

  function getFilteredItems(list: ItemRow[], query: string) {
    const normalizedQuery = normalizeSearchValue(query);
    if (!normalizedQuery) {
      return list;
    }

    return list
      .map((item) => ({
        item,
        score: getItemSearchScore(item, normalizedQuery),
      }))
      .filter(({ score }) => score > 0)
      .sort((a, b) => b.score - a.score)
      .map(({ item }) => item);
  }

  function shouldShowDescriptionToggle(description: string, maxLength: number) {
    return description.trim().length > maxLength;
  }

  function toggleTableDescription(itemId: string) {
    expandedTableDescriptions = {
      ...expandedTableDescriptions,
      [itemId]: !expandedTableDescriptions[itemId],
    };
  }

  function toggleCardDescription(itemId: string) {
    expandedCardDescriptions = {
      ...expandedCardDescriptions,
      [itemId]: !expandedCardDescriptions[itemId],
    };
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
      submitterEmails = {};
      return;
    }

    const { data, error } = await supabase.from("profiles").select("role").eq("id", userId).maybeSingle();

    if (error) {
      userRole = null;
      return;
    }

    userRole = (data?.role as UserRole | null) ?? "user";

    if (userRole === "librarian") {
      await loadSubmitterEmails();
    } else {
      submitterEmails = {};
    }
  }

  async function loadSubmitterEmails() {
    const { data, error } = await supabase.rpc("list_profiles_with_email");
    if (error || !data) return;
    const map: Record<string, string> = {};
    for (const row of data as { id: string; email: string | null }[]) {
      if (row.email) map[row.id] = row.email;
    }
    submitterEmails = map;
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

<svelte:window on:click={handleWindowClick} on:keydown={handleKeydown} />

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="relative z-40 border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-6xl px-4 py-4 md:py-5">
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div class="text-left">
          <h1 class="text-left text-2xl font-bold leading-tight md:text-3xl">Library Lost &amp; Found</h1>
          <p class="mt-1 text-sm text-muted-foreground">Browse reported items and check their status.</p>
        </div>

        <div class="flex items-center gap-3 md:justify-end">
          {#if session}
            <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
              <div class="text-sm text-muted-foreground">
                Signed in as <strong>{session.user.email}</strong>
              </div>
              <Badge variant="outline" class="w-fit border-primary/40 text-sm uppercase tracking-wide">
                {userRole ?? "unknown"}
              </Badge>
            </div>
          {:else}
            <Button class="w-full text-sm sm:w-auto" onclick={handleGoogleSignIn} disabled={authLoading}>
              {authLoading ? "Redirecting..." : "Sign in to report an item"}
            </Button>
          {/if}

          <div class="relative" bind:this={menuContainer}>
            <Button
              variant="outline"
              size="icon"
              class="bg-background"
              onclick={toggleMenu}
              aria-label="Open menu"
              aria-haspopup="menu"
              aria-expanded={menuOpen}
            >
              <EllipsisVertical size={20} />
            </Button>

            {#if menuOpen}
              <div
                role="menu"
                class="absolute right-0 top-full z-50 mt-2 w-56 rounded-md border border-border/80 bg-popover text-popover-foreground shadow-md"
              >
                <button
                  type="button"
                  role="menuitem"
                  class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-accent hover:text-accent-foreground"
                  onclick={() => {
                    toggleTheme();
                    closeMenu();
                  }}
                >
                  {#if isDark}
                    <Sun size={16} />
                    <span>Light mode</span>
                  {:else}
                    <Moon size={16} />
                    <span>Dark mode</span>
                  {/if}
                </button>

                {#if session && isLibrarian}
                  <a
                    href="/librarians"
                    role="menuitem"
                    class="flex w-full items-center gap-2 border-t border-border/80 px-3 py-2 text-left text-sm hover:bg-accent hover:text-accent-foreground"
                    onclick={closeMenu}
                  >
                    <Users size={16} />
                    <span>Manage librarians</span>
                  </a>
                {/if}

                {#if session}
                  <button
                    type="button"
                    role="menuitem"
                    class="flex w-full items-center gap-2 border-t border-border/80 px-3 py-2 text-left text-sm hover:bg-accent hover:text-accent-foreground disabled:opacity-50"
                    disabled={authLoading}
                    onclick={() => {
                      handleLogout();
                      closeMenu();
                    }}
                  >
                    <LogOut size={16} />
                    <span>Log out</span>
                  </button>
                {/if}
              </div>
            {/if}
          </div>
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
      <Alert class="mb-6 border-primary/40 bg-primary/10 py-3 text-sm">
        <AlertTitle>Librarian View</AlertTitle>
        <AlertDescription>
          You can update statuses, review archived records, and remove reports.
        </AlertDescription>
      </Alert>
    {/if}

    <Card class="border-border/80 bg-card text-sm shadow-none">
      <CardHeader class="gap-3">
        <div class="flex flex-col gap-1 md:flex-row md:items-end md:justify-between">
          <div class="space-y-1">
            <CardTitle class="text-xl md:text-2xl">
              {viewingDeleted ? "Archived records" : "Reported items"}
            </CardTitle>
            {#if searchQuery.trim()}
              <CardDescription class="text-sm">
                {filteredDisplayedItems.length} result{filteredDisplayedItems.length === 1 ? "" : "s"} for "{searchQuery.trim()}"
              </CardDescription>
            {/if}
          </div>
        </div>
      </CardHeader>
      <Separator class="bg-border/80" />
      <CardContent class="px-0 pb-5">
        <div class="px-4">
          <div class="mb-5 flex flex-col gap-3">
            <div class="flex flex-col gap-3 lg:flex-row lg:items-center">
              <div class="relative flex-1">
                <Search
                  size={16}
                  class="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground"
                />
                <Input
                  type="search"
                  bind:value={searchQuery}
                  class="h-10 bg-background pl-8 text-sm md:text-sm"
                  placeholder={viewingDeleted ? "Search archived items" : "Search by title, category, location, or description"}
                  aria-label={viewingDeleted ? "Search archived items" : "Search reported items"}
                />
              </div>

              <div class="flex flex-wrap items-center gap-2 lg:shrink-0">
                <Button variant="ghost" class="text-sm" onclick={loadItems} disabled={itemsLoading}>Refresh</Button>
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
              </div>
            </div>

            <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div class="flex flex-wrap gap-4">
                {#if isLibrarian}
                  <div class="space-y-1">
                    <p class="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Scope</p>
                    <div class="flex w-fit items-center overflow-hidden border border-border/80 bg-background">
                      <Button
                        variant={viewingDeleted ? "ghost" : "secondary"}
                        class="rounded-none border-0 text-sm"
                        onclick={() => setViewingDeleted(false)}
                        disabled={itemsLoading && !viewingDeleted}
                        aria-pressed={!viewingDeleted}
                      >
                        Public
                      </Button>
                      <Button
                        variant={viewingDeleted ? "secondary" : "ghost"}
                        class="rounded-none border-0 border-l border-border/80 text-sm"
                        onclick={() => setViewingDeleted(true)}
                        disabled={itemsLoading && viewingDeleted}
                        aria-pressed={viewingDeleted}
                      >
                        Archived
                      </Button>
                    </div>
                  </div>
                {/if}

                <div class="space-y-1">
                  <p class="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Layout</p>
                  <div class="flex w-fit items-center overflow-hidden border border-border/80 bg-background">
                    <Button
                      variant={viewMode === "cards" ? "secondary" : "ghost"}
                      class="rounded-none border-0 text-sm"
                      onclick={() => (viewMode = "cards")}
                      aria-pressed={viewMode === "cards"}
                    >
                      Cards
                    </Button>
                    <Button
                      variant={viewMode === "table" ? "secondary" : "ghost"}
                      class="rounded-none border-0 border-l border-border/80 text-sm"
                      onclick={() => (viewMode = "table")}
                      aria-pressed={viewMode === "table"}
                    >
                      Table
                    </Button>
                  </div>
                </div>
              </div>

              {#if viewingDeleted && isLibrarian}
                <p class="text-xs text-muted-foreground lg:pt-6">Archived records are visible only to librarians.</p>
              {/if}
            </div>
          </div>
        </div>

        <Separator class="bg-border/80" />

        <div class="px-4 pt-5">
        {#if itemsLoading}
          <p class="text-muted-foreground">Loading items...</p>
        {:else if itemsError}
          <Alert variant="destructive" class="text-sm">
            <AlertTitle>Could not load items</AlertTitle>
            <AlertDescription>{itemsError}</AlertDescription>
          </Alert>
        {:else if displayedItems.length === 0}
          <p class="italic text-muted-foreground">No reports yet. Add the first item report.</p>
        {:else if filteredDisplayedItems.length === 0}
          <p class="italic text-muted-foreground">No items match that search.</p>
        {:else}
          {#if viewMode === "cards"}
            <div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-3">
              {#each filteredDisplayedItems as item (item.id)}
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
                    <div class="flex items-start justify-between gap-3">
                      <h3 class="text-base font-semibold md:text-lg">{item.title}</h3>
                      <Badge class={`${statusBadgeVariant(item.status)} text-sm`}>
                        {item.status}
                      </Badge>
                    </div>
                    <div>
                      <p class={`text-sm text-muted-foreground ${expandedCardDescriptions[item.id] ? "" : "line-clamp-4"}`}>
                        {item.description}
                      </p>
                      {#if shouldShowDescriptionToggle(item.description, 220)}
                        <button
                          type="button"
                          class="mt-1 text-xs font-medium text-primary hover:underline"
                          onclick={() => toggleCardDescription(item.id)}
                          aria-expanded={expandedCardDescriptions[item.id] ? "true" : "false"}
                        >
                          {expandedCardDescriptions[item.id] ? "Show less" : "Show more"}
                        </button>
                      {/if}
                    </div>
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
                      {#if isLibrarian && submitterEmails[item.created_by]}
                        <a
                          href={`mailto:${submitterEmails[item.created_by]}?subject=${encodeURIComponent(`Re: ${item.title}`)}`}
                          class="inline-flex max-w-full items-center gap-2 rounded-full bg-muted/55 px-2.5 py-1.5 hover:bg-muted"
                          title={`Email submitter: ${submitterEmails[item.created_by]}`}
                          aria-label={`Email submitter: ${submitterEmails[item.created_by]}`}
                        >
                          <Mail size={15} class="shrink-0 text-primary" />
                          <span class="truncate">{submitterEmails[item.created_by]}</span>
                        </a>
                      {/if}
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
          {:else}
            <div class="overflow-x-auto rounded-md border border-border/80">
              <table class="w-full min-w-[820px] border-collapse text-left text-sm table-fixed">
                <colgroup>
                  <col class="w-[42%]" />
                  <col class="w-[11%]" />
                  <col class="w-[11%]" />
                  <col class="w-[14%]" />
                  <col class="w-[14%]" />
                  {#if isLibrarian}
                    <col class="w-[14%]" />
                  {/if}
                  <col class="w-[8%]" />
                </colgroup>
                <thead class="bg-muted/40 text-muted-foreground">
                  <tr>
                    <th class="px-4 py-3 font-medium">Item</th>
                    <th class="px-4 py-3 font-medium">Status</th>
                    <th class="px-4 py-3 font-medium">Category</th>
                    <th class="px-4 py-3 font-medium">Location</th>
                    <th class="px-4 py-3 font-medium">Reported</th>
                    {#if isLibrarian}
                      <th class="px-4 py-3 font-medium">Submitter</th>
                    {/if}
                    <th class="px-4 py-3 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {#each filteredDisplayedItems as item (item.id)}
                    {@const showItemActions =
                      !viewingDeleted && (isLibrarian || (session && session.user.id === item.created_by))}
                    <tr class="border-t border-border/80 align-top">
                      <td class="px-4 py-4">
                        <div class="flex items-start gap-3">
                          {#if item.image_url}
                            <img src={item.image_url} alt={item.title} class="h-12 w-12 rounded-sm object-cover shrink-0" />
                          {:else}
                            <div class="flex h-12 w-12 items-center justify-center rounded-sm bg-muted text-xs text-muted-foreground shrink-0">
                              None
                            </div>
                          {/if}
                          <div class="min-w-0 flex-1 space-y-1">
                            <div class="truncate pr-2 font-medium">{item.title}</div>
                            <div class="max-w-none">
                              <p class={`text-muted-foreground ${expandedTableDescriptions[item.id] ? "" : "line-clamp-2"}`}>
                                {item.description}
                              </p>
                              {#if shouldShowDescriptionToggle(item.description, 120)}
                                <button
                                  type="button"
                                  class="mt-1 text-xs font-medium text-primary hover:underline"
                                  onclick={() => toggleTableDescription(item.id)}
                                  aria-expanded={expandedTableDescriptions[item.id] ? "true" : "false"}
                                >
                                  {expandedTableDescriptions[item.id] ? "Show less" : "Show more"}
                                </button>
                              {/if}
                            </div>
                          </div>
                        </div>
                      </td>
                      <td class="px-4 py-4">
                        <Badge class={`${statusBadgeVariant(item.status)} text-sm`}>
                          {item.status}
                        </Badge>
                      </td>
                      <td class="px-4 py-4">
                        <div class="w-full">
                          <span class="block truncate" title={item.category}>{item.category}</span>
                        </div>
                      </td>
                      <td class="px-4 py-4">
                        <div class="w-full">
                          <span class="block truncate" title={item.location_found ?? "Unknown"}>{item.location_found ?? "Unknown"}</span>
                        </div>
                      </td>
                      <td class="px-4 py-4 whitespace-nowrap">
                        <div class="w-full">
                          <span class="block truncate" title={formatItemDate(item.created_at)}>{formatItemDate(item.created_at)}</span>
                        </div>
                      </td>
                      {#if isLibrarian}
                        <td class="px-4 py-4">
                          {#if submitterEmails[item.created_by]}
                            <div class="w-full">
                              <a
                                href={`mailto:${submitterEmails[item.created_by]}?subject=${encodeURIComponent(`Re: ${item.title}`)}`}
                                class="inline-flex w-full min-w-0 items-center gap-2 text-primary hover:underline"
                                title={submitterEmails[item.created_by]}
                              >
                                <Mail size={15} class="shrink-0" />
                                <span class="block truncate">{submitterEmails[item.created_by]}</span>
                              </a>
                            </div>
                          {:else}
                            <span class="text-muted-foreground">Unavailable</span>
                          {/if}
                        </td>
                      {/if}
                      <td class="px-4 py-4">
                        {#if showItemActions}
                          <details class="relative">
                            <summary
                              class="flex h-8 w-8 cursor-pointer list-none items-center justify-center rounded-sm border border-border/80 bg-background text-muted-foreground hover:bg-muted [&::-webkit-details-marker]:hidden"
                              aria-label={`Open actions for ${item.title}`}
                            >
                              <EllipsisVertical size={16} />
                            </summary>
                            <div class="absolute right-0 top-10 z-20 w-56 rounded-md border border-border/80 bg-popover p-2 shadow-md">
                              {#if isLibrarian}
                                <div class="space-y-1">
                                  <p class="px-2 pt-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                                    Status
                                  </p>
                                  <Select
                                    type="single"
                                    value={item.status}
                                    onValueChange={(value: string) => updateItemStatus(item.id, value as ItemStatus)}
                                  >
                                    <SelectTrigger class="w-full bg-background text-sm">
                                      {item.status}
                                    </SelectTrigger>
                                    <SelectContent>
                                      {#each statusOptions as option}
                                        <SelectItem value={option} label={option} />
                                      {/each}
                                    </SelectContent>
                                  </Select>
                                </div>
                              {/if}
                              <div class="mt-2 flex flex-col gap-1">
                                {#if session && session.user.id === item.created_by}
                                  <Button href="/edit/{item.id}" variant="outline" size="sm" class="justify-start text-sm">Edit item</Button>
                                {/if}
                                <Button
                                  variant="destructive"
                                  size="sm"
                                  class="justify-start text-sm"
                                  onclick={() => {
                                    if (confirm("Archive and remove this item from the public list?")) {
                                      deleteItem(item.id);
                                    }
                                  }}
                                >
                                  {isLibrarian ? "Archive item" : "Delete item"}
                                </Button>
                              </div>
                            </div>
                          </details>
                        {:else}
                          <span class="text-muted-foreground">No actions</span>
                        {/if}
                      </td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          {/if}
        {/if}
        </div>
      </CardContent>
    </Card>
  </main>
</div>
