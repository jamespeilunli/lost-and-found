<script lang="ts">
  import { onMount } from "svelte";
  import {
    AlarmClock,
    CalendarDays,
    Edit3,
    Filter,
    Info,
    LayoutGrid,
    List,
    LogOut,
    Mail,
    MapPin,
    Moon,
    Plus,
    RefreshCw,
    Search,
    Sun,
    Tag,
    Trash2,
    Users,
  } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { publicSupabase, supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Badge } from "$lib/components/ui/badge";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "$lib/components/ui/card";
  import { Input } from "$lib/components/ui/input";
  import { Label } from "$lib/components/ui/label";
  import { Separator } from "$lib/components/ui/separator";

  type ItemStatus = "found" | "claimed";
  type ViewMode = "cards" | "table";

  type ItemRow = {
    id: string;
    title: string;
    description: string | null;
    category: string | null;
    status: ItemStatus;
    image_url: string | null;
    location_found: string | null;
    created_at: string;
    created_by?: string | null;
    manual_due_date: string | null;
  };

  const activeStatusOptions: ItemStatus[] = ["found", "claimed"];
  const itemSelectColumns = "id,title,description,category,status,image_url,location_found,created_at,manual_due_date";
  const publicItemSelectColumns = "id,title,description,category,status,image_url,location_found,created_at,manual_due_date";
  const GRACE_PERIOD_DAYS = 14;

  const statusLabels: Record<ItemStatus, string> = {
    found: "At library",
    claimed: "Claimed",
  };

  let session: Session | null = null;
  let authChecked = false;
  let authLoading = false;
  let authError = "";
  let authMessage = "";
  let authMode: "signin" | "reset" = "signin";
  let email = "";
  let password = "";

  let items: ItemRow[] = [];
  let deletedItems: ItemRow[] = [];
  let itemsLoading = false;
  let itemsError = "";
  let viewingDeleted = false;
  let searchQuery = "";
  let viewMode: ViewMode = "cards";
  let selectedStatusFilters: ItemStatus[] = ["found"];
  let pendingItemId: string | null = null;
  let dueDateDrafts: Record<string, string> = {};
  let loadItemsRequestId = 0;

  let isDark = false;
  let now = new Date();

  $: isSignedIn = Boolean(session);
  $: displayedItems = viewingDeleted ? deletedItems : items;
  $: filteredDisplayedItems = getFilteredItems(displayedItems, searchQuery, selectedStatusFilters);
  $: statusSummary =
    selectedStatusFilters.length === activeStatusOptions.length
      ? "All statuses"
      : selectedStatusFilters.map((status) => statusLabels[status]).join(", ");

  function statusBadgeClass(status: ItemStatus) {
    return status === "found"
      ? "bg-emerald-100 text-emerald-900 uppercase dark:bg-emerald-950 dark:text-emerald-300"
      : "bg-sky-100 text-sky-900 uppercase dark:bg-sky-950 dark:text-sky-300";
  }

  function normalizeSearchValue(value: string | null | undefined) {
    return (value ?? "")
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  function getFilteredItems(list: ItemRow[], query: string, selectedStatuses: ItemStatus[]) {
    const selected = new Set(selectedStatuses);
    const normalizedQuery = normalizeSearchValue(query);

    return list.filter((item) => {
      if (!selected.has(item.status)) return false;
      if (!normalizedQuery) return true;

      const text = normalizeSearchValue(
        [item.title, item.description, item.category, item.location_found, statusLabels[item.status]].join(" "),
      );
      return normalizedQuery.split(" ").every((token) => text.includes(token));
    });
  }

  function getAutomaticDueDate(createdAt: string) {
    const eligibleFrom = new Date(createdAt);
    eligibleFrom.setDate(eligibleFrom.getDate() + GRACE_PERIOD_DAYS);
    return new Date(eligibleFrom.getFullYear(), eligibleFrom.getMonth() + 1, 0, 23, 59, 59, 999);
  }

  function parseManualDueDate(value: string | null) {
    if (!value) return null;
    const [year, month, day] = value.split("-").map(Number);
    if (!year || !month || !day) return null;
    return new Date(year, month - 1, day, 23, 59, 59, 999);
  }

  function getEffectiveDueDate(item: ItemRow) {
    return parseManualDueDate(item.manual_due_date) ?? getAutomaticDueDate(item.created_at);
  }

  function formatDate(value: string | Date) {
    const date = value instanceof Date ? value : new Date(value);
    return date.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
  }

  function formatDateTime(value: string) {
    return new Date(value).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  }

  function formatDeadline(item: ItemRow) {
    const dueDate = getEffectiveDueDate(item);
    const ms = dueDate.getTime() - now.getTime();
    const days = Math.max(0, Math.ceil(ms / 86400000));
    return `${formatDate(dueDate)}${days === 0 ? " · due today" : ` · ${days}d left`}`;
  }

  function syncDueDateDrafts(list: ItemRow[]) {
    dueDateDrafts = Object.fromEntries(list.map((item) => [item.id, item.manual_due_date ?? ""]));
  }

  function isAuthorizationError(message: string) {
    const normalized = message.toLowerCase();
    return normalized.includes("row-level security") || normalized.includes("permission denied") || normalized.includes("librarian access");
  }

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    authChecked = true;
    selectedStatusFilters = session ? [...activeStatusOptions] : ["found"];
    return session;
  }

  async function loadItems(options: { signedIn?: boolean; showDeleted?: boolean } = {}) {
    const signedIn = options.signedIn ?? isSignedIn;
    const showDeleted = signedIn && (options.showDeleted ?? viewingDeleted);
    const requestId = ++loadItemsRequestId;

    itemsLoading = true;
    itemsError = "";
    authError = "";

    if (!signedIn) {
      viewingDeleted = false;
      deletedItems = [];
      selectedStatusFilters = ["found"];
    }

    const query = signedIn
      ? supabase
          .from(showDeleted ? "deleted_items" : "items")
          .select(itemSelectColumns)
          .in("status", activeStatusOptions)
          .order("created_at", { ascending: false })
      : publicSupabase
          .from("items")
          .select(publicItemSelectColumns)
          .eq("status", "found")
          .order("created_at", { ascending: false });

    const { data, error } = await query;

    if (requestId !== loadItemsRequestId) return;

    if (error) {
      const message = error.message;
      itemsError = message;
      if (isAuthorizationError(message)) {
        authError = "This signed-in account is not approved for librarian tools.";
      }
      if (showDeleted) {
        deletedItems = [];
      } else {
        items = [];
      }
    } else {
      const fetchedItems = ((data ?? []) as ItemRow[]).sort(
        (a, b) => getEffectiveDueDate(a).getTime() - getEffectiveDueDate(b).getTime(),
      );

      if (showDeleted) {
        deletedItems = fetchedItems;
      } else {
        items = fetchedItems;
      }
      syncDueDateDrafts(fetchedItems);
    }

    itemsLoading = false;
  }

  async function handleSignIn() {
    authLoading = true;
    authError = "";
    authMessage = "";

    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    if (error) {
      authError = error.message;
    } else {
      session = data.session;
      selectedStatusFilters = [...activeStatusOptions];
      await loadItems({ signedIn: true, showDeleted: false });
    }

    authLoading = false;
  }

  async function handlePasswordReset() {
    authLoading = true;
    authError = "";
    authMessage = "";

    const redirectTo = `${window.location.origin}/set-password`;
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo });

    if (error) {
      authError = error.message;
    } else {
      authMessage = "Check your email for a password reset link.";
    }

    authLoading = false;
  }

  async function handleLogout() {
    authLoading = true;
    authError = "";
    authMessage = "";
    session = null;
    viewingDeleted = false;
    deletedItems = [];
    selectedStatusFilters = ["found"];

    const { error } = await supabase.auth.signOut();
    if (error) {
      authError = error.message;
    }

    await loadItems({ signedIn: false, showDeleted: false });
    authLoading = false;
  }

  async function setViewingDeleted(nextValue: boolean) {
    if (!session) return;
    viewingDeleted = nextValue;
    await loadItems({ signedIn: true, showDeleted: nextValue });
  }

  async function updateItemStatus(itemId: string, nextStatus: ItemStatus) {
    if (!session) return;

    pendingItemId = itemId;
    const { data, error } = await supabase
      .from("items")
      .update({ status: nextStatus })
      .eq("id", itemId)
      .select(itemSelectColumns)
      .single();
    pendingItemId = null;

    if (error) {
      toast.error(`Could not update status: ${error.message}`);
      itemsError = error.message;
      return;
    }

    items = items.map((item) => (item.id === itemId ? (data as ItemRow) : item));
    syncDueDateDrafts(items);
    toast.success(`Item marked ${statusLabels[nextStatus].toLowerCase()}.`);
  }

  async function updateItemDueDate(itemId: string) {
    if (!session) return;

    const nextDueDate = dueDateDrafts[itemId]?.trim() || null;
    pendingItemId = itemId;
    const { data, error } = await supabase
      .from("items")
      .update({ manual_due_date: nextDueDate })
      .eq("id", itemId)
      .select(itemSelectColumns)
      .single();
    pendingItemId = null;

    if (error) {
      toast.error(`Could not update deadline: ${error.message}`);
      itemsError = error.message;
      return;
    }

    items = items.map((item) => (item.id === itemId ? (data as ItemRow) : item));
    syncDueDateDrafts(items);
    toast.success(nextDueDate ? "Pickup deadline updated." : "Pickup deadline returned to automatic.");
  }

  async function archiveItem(itemId: string) {
    if (!session) return;

    const item = items.find((candidate) => candidate.id === itemId);
    if (!item) return;

    pendingItemId = itemId;
    const archivedItem = {
      id: item.id,
      title: item.title,
      description: item.description,
      category: item.category,
      status: item.status,
      image_url: item.image_url,
      location_found: item.location_found,
      created_at: item.created_at,
      created_by: item.created_by ?? session.user.id,
      manual_due_date: item.manual_due_date,
    };

    const { error: insertError } = await supabase.from("deleted_items").insert([archivedItem]);
    if (insertError) {
      pendingItemId = null;
      toast.error(`Could not archive item: ${insertError.message}`);
      itemsError = insertError.message;
      return;
    }

    const { error: deleteError } = await supabase.from("items").delete().eq("id", itemId);
    pendingItemId = null;

    if (deleteError) {
      toast.error(`Archived item, but active removal failed: ${deleteError.message}`);
      itemsError = deleteError.message;
      return;
    }

    items = items.filter((candidate) => candidate.id !== itemId);
    syncDueDateDrafts(items);
    toast.success("Item archived.");
  }

  function toggleTheme() {
    isDark = !isDark;
    document.documentElement.classList.toggle("dark", isDark);
    localStorage.setItem("theme", isDark ? "dark" : "light");
  }

  function toggleStatusFilter(status: ItemStatus) {
    if (!session && status !== "found") return;
    selectedStatusFilters = selectedStatusFilters.includes(status)
      ? selectedStatusFilters.filter((candidate) => candidate !== status)
      : [...selectedStatusFilters, status];
  }

  onMount(() => {
    isDark = document.documentElement.classList.contains("dark");

    void (async () => {
      await loadItems({ signedIn: false, showDeleted: false });
      const restoredSession = await loadSession();
      if (restoredSession) {
        await loadItems({ signedIn: true, showDeleted: false });
      }
    })();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      session = nextSession;
      authChecked = true;
      viewingDeleted = false;
      selectedStatusFilters = nextSession ? [...activeStatusOptions] : ["found"];
      void loadItems({ signedIn: Boolean(nextSession), showDeleted: false });
    });

    const clockInterval = setInterval(() => {
      now = new Date();
    }, 60000);

    return () => {
      data.subscription.unsubscribe();
      clearInterval(clockInterval);
    };
  });
</script>

<svelte:head>
  <title>Library Lost &amp; Found</title>
  <meta name="description" content="Browse and manage library lost and found records." />
</svelte:head>

<div class="min-h-screen bg-background text-foreground">
  <header class="border-b bg-card/95">
    <div class="mx-auto flex max-w-6xl flex-col gap-5 px-4 py-5 lg:flex-row lg:items-start lg:justify-between">
      <div class="flex items-center gap-3">
        <img
          src={isDark ? "/faviconDark.png" : "/favicon.png"}
          alt="MVHS logo"
          class="h-12 w-12 shrink-0 object-contain md:h-14 md:w-14"
        />
        <div>
          <h1 class="text-2xl font-bold leading-tight md:text-3xl">Library Lost &amp; Found</h1>
          <p class="mt-1 text-sm text-muted-foreground">
            {session ? "Manage library inventory." : "Browse items currently at the library."}
          </p>
        </div>
      </div>

      <div class="w-full max-w-xl lg:w-[520px]">
        {#if session}
          <div class="flex flex-col gap-3 border border-border/80 bg-background p-3 text-sm sm:flex-row sm:items-center sm:justify-between">
            <div class="min-w-0">
              <p class="truncate text-muted-foreground">Signed in as <strong>{session.user.email}</strong></p>
              <Badge variant="outline" class="mt-1 border-primary/40 uppercase tracking-wide">librarian session</Badge>
            </div>
            <div class="flex shrink-0 gap-2">
              <Button href="/librarians" variant="outline" size="sm" class="gap-1.5">
                <Users size={16} />
                Librarians
              </Button>
              <Button variant="outline" size="sm" class="gap-1.5" onclick={handleLogout} disabled={authLoading}>
                <LogOut size={16} />
                Logout
              </Button>
            </div>
          </div>
        {:else}
          <form
            class="border border-border/80 bg-background p-3"
            onsubmit={(event) => {
              event.preventDefault();
              void (authMode === "signin" ? handleSignIn() : handlePasswordReset());
            }}
          >
            <div class="grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end">
              <div class="space-y-1.5">
                <Label for="email-input" class="text-xs">Email</Label>
                <Input id="email-input" type="email" autocomplete="email" bind:value={email} />
              </div>
              {#if authMode === "signin"}
                <div class="space-y-1.5">
                  <Label for="password-input" class="text-xs">Password</Label>
                  <Input id="password-input" type="password" autocomplete="current-password" bind:value={password} />
                </div>
              {/if}
              <Button type="submit" class="gap-1.5" disabled={authLoading || !email.trim() || (authMode === "signin" && !password)}>
                <Mail size={16} />
                {authLoading ? "Working..." : authMode === "signin" ? "Sign in" : "Send reset"}
              </Button>
            </div>
            <div class="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs">
              <button
                type="button"
                class="text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
                onclick={() => {
                  authMode = authMode === "signin" ? "reset" : "signin";
                  authError = "";
                  authMessage = "";
                }}
              >
                {authMode === "signin" ? "Forgot password?" : "Back to sign in"}
              </button>
              <span class="text-muted-foreground">Librarian accounts are invite-only.</span>
            </div>
          </form>
        {/if}
      </div>
    </div>
  </header>

  <main class="mx-auto max-w-6xl px-4 py-6">
    {#if authError}
      <Alert variant="destructive" class="mb-4 text-sm">
        <AlertTitle>Authentication issue</AlertTitle>
        <AlertDescription>{authError}</AlertDescription>
      </Alert>
    {/if}

    {#if authMessage}
      <Alert class="mb-4 text-sm">
        <AlertTitle>Email sent</AlertTitle>
        <AlertDescription>{authMessage}</AlertDescription>
      </Alert>
    {/if}

    <section class="mb-4 grid gap-3 border border-border/80 bg-card p-3 lg:grid-cols-[1fr_auto] lg:items-center">
      <div class="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto_auto] md:items-center">
        <div class="relative">
          <Search size={16} class="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <Input type="search" placeholder="Search inventory" bind:value={searchQuery} class="pl-9" />
        </div>

        <div class="flex min-h-10 items-center gap-1 border border-border/80 bg-background px-2">
          <Filter size={15} class="text-muted-foreground" />
          <span class="mr-1 text-xs text-muted-foreground">{statusSummary || "No statuses"}</span>
          {#each activeStatusOptions as status}
            <button
              type="button"
              class={`px-2 py-1 text-xs uppercase ${selectedStatusFilters.includes(status) ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"} ${!session && status === "claimed" ? "opacity-40" : ""}`}
              disabled={!session && status === "claimed"}
              onclick={() => toggleStatusFilter(status)}
            >
              {statusLabels[status]}
            </button>
          {/each}
        </div>

        <div class="flex gap-1">
          <Button variant={viewMode === "cards" ? "default" : "outline"} size="icon" aria-label="Card view" onclick={() => (viewMode = "cards")}>
            <LayoutGrid size={17} />
          </Button>
          <Button variant={viewMode === "table" ? "default" : "outline"} size="icon" aria-label="Table view" onclick={() => (viewMode = "table")}>
            <List size={17} />
          </Button>
          <Button variant="outline" size="icon" aria-label="Toggle theme" onclick={toggleTheme}>
            {#if isDark}
              <Sun size={17} />
            {:else}
              <Moon size={17} />
            {/if}
          </Button>
        </div>
      </div>

      <div class="flex flex-wrap gap-2 lg:justify-end">
        {#if session}
          <Button href="/log-found" class="gap-1.5">
            <Plus size={16} />
            Log item
          </Button>
          <Button variant={viewingDeleted ? "default" : "outline"} class="gap-1.5" onclick={() => setViewingDeleted(!viewingDeleted)}>
            <Trash2 size={16} />
            {viewingDeleted ? "Active inventory" : "Archive"}
          </Button>
        {/if}
        <Button variant="outline" class="gap-1.5" onclick={() => loadItems({ signedIn: isSignedIn, showDeleted: viewingDeleted })} disabled={itemsLoading}>
          <RefreshCw size={16} />
          Refresh
        </Button>
        <Button href="/about" variant="ghost" size="icon" aria-label="About">
          <Info size={17} />
        </Button>
      </div>
    </section>

    {#if itemsError}
      <Alert variant="destructive" class="mb-4 text-sm">
        <AlertTitle>Could not load inventory</AlertTitle>
        <AlertDescription>{itemsError}</AlertDescription>
      </Alert>
    {/if}

    {#if !authChecked || itemsLoading}
      <p class="py-10 text-center text-sm text-muted-foreground">Loading inventory...</p>
    {:else if filteredDisplayedItems.length === 0}
      <div class="border border-dashed border-border/80 bg-card px-4 py-12 text-center">
        <p class="font-medium">{viewingDeleted ? "No archived records match." : "No items match."}</p>
        <p class="mt-1 text-sm text-muted-foreground">Try a different search or status filter.</p>
      </div>
    {:else if viewMode === "table"}
      <div class="overflow-x-auto border border-border/80 bg-card">
        <table class="w-full min-w-[860px] text-left text-sm">
          <thead class="border-b bg-muted/60 text-xs uppercase text-muted-foreground">
            <tr>
              <th class="px-3 py-2">Item</th>
              <th class="px-3 py-2">Status</th>
              <th class="px-3 py-2">Location</th>
              <th class="px-3 py-2">Deadline</th>
              <th class="px-3 py-2">Logged</th>
              {#if session && !viewingDeleted}
                <th class="px-3 py-2 text-right">Actions</th>
              {/if}
            </tr>
          </thead>
          <tbody>
            {#each filteredDisplayedItems as item (item.id)}
              <tr class="border-b last:border-b-0">
                <td class="max-w-[320px] px-3 py-3">
                  <div class="font-medium">{item.title}</div>
                  <div class="mt-1 line-clamp-2 text-xs text-muted-foreground">{item.description || "No description"}</div>
                </td>
                <td class="px-3 py-3">
                  <Badge class={statusBadgeClass(item.status)}>{statusLabels[item.status]}</Badge>
                </td>
                <td class="px-3 py-3 text-muted-foreground">{item.location_found || "Library"}</td>
                <td class="px-3 py-3">
                  {#if session && !viewingDeleted && item.status === "found"}
                    <div class="flex gap-2">
                      <Input type="date" class="h-8 w-36 text-xs" bind:value={dueDateDrafts[item.id]} />
                      <Button size="sm" variant="outline" onclick={() => updateItemDueDate(item.id)} disabled={pendingItemId === item.id}>Save</Button>
                    </div>
                  {:else}
                    <span class="text-muted-foreground">{formatDeadline(item)}</span>
                  {/if}
                </td>
                <td class="px-3 py-3 text-muted-foreground">{formatDateTime(item.created_at)}</td>
                {#if session && !viewingDeleted}
                  <td class="px-3 py-3">
                    <div class="flex justify-end gap-2">
                      <Button href={`/edit/${item.id}`} size="sm" variant="outline">Edit</Button>
                      <Button
                        size="sm"
                        variant="outline"
                        onclick={() => updateItemStatus(item.id, item.status === "found" ? "claimed" : "found")}
                        disabled={pendingItemId === item.id}
                      >
                        {item.status === "found" ? "Claim" : "Restore"}
                      </Button>
                      <Button size="sm" variant="outline" onclick={() => archiveItem(item.id)} disabled={pendingItemId === item.id}>Archive</Button>
                    </div>
                  </td>
                {/if}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {:else}
      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {#each filteredDisplayedItems as item (item.id)}
          <Card class="flex min-h-[420px] flex-col overflow-hidden border-border/80 bg-card shadow-none">
            <div class="aspect-[4/3] bg-muted">
              {#if item.image_url}
                <img src={item.image_url} alt={item.title} class="h-full w-full object-cover" />
              {:else}
                <div class="flex h-full items-center justify-center text-sm text-muted-foreground">No image</div>
              {/if}
            </div>
            <CardHeader class="space-y-3">
              <div class="flex items-start justify-between gap-3">
                <CardTitle class="min-w-0 text-lg leading-snug">{item.title}</CardTitle>
                <Badge class={statusBadgeClass(item.status)}>{statusLabels[item.status]}</Badge>
              </div>
              <div class="flex flex-wrap gap-2 text-xs text-muted-foreground">
                <span class="inline-flex items-center gap-1">
                  <Tag size={13} />
                  {item.category || "Other"}
                </span>
                <span class="inline-flex items-center gap-1">
                  <MapPin size={13} />
                  {item.location_found || "Library"}
                </span>
              </div>
            </CardHeader>
            <CardContent class="flex-1 space-y-4">
              <p class="text-sm text-muted-foreground">{item.description || "No description provided."}</p>
              <Separator />
              <div class="space-y-2 text-sm">
                <div class="flex items-center gap-2 text-muted-foreground">
                  <CalendarDays size={15} />
                  Logged {formatDateTime(item.created_at)}
                </div>
                <div class="flex items-center gap-2 text-muted-foreground">
                  <AlarmClock size={15} />
                  {formatDeadline(item)}
                </div>
                {#if session && !viewingDeleted && item.status === "found"}
                  <div class="flex gap-2 pt-1">
                    <Input type="date" class="h-9 text-sm" bind:value={dueDateDrafts[item.id]} />
                    <Button size="sm" variant="outline" onclick={() => updateItemDueDate(item.id)} disabled={pendingItemId === item.id}>
                      Save
                    </Button>
                  </div>
                {/if}
              </div>
            </CardContent>
            {#if session && !viewingDeleted}
              <CardFooter class="flex flex-wrap justify-between gap-2 border-t pt-4">
                <Button href={`/edit/${item.id}`} variant="outline" size="sm" class="gap-1.5">
                  <Edit3 size={14} />
                  Edit
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onclick={() => updateItemStatus(item.id, item.status === "found" ? "claimed" : "found")}
                  disabled={pendingItemId === item.id}
                >
                  {item.status === "found" ? "Mark claimed" : "Mark at library"}
                </Button>
                <Button variant="outline" size="sm" onclick={() => archiveItem(item.id)} disabled={pendingItemId === item.id}>
                  Archive
                </Button>
              </CardFooter>
            {/if}
          </Card>
        {/each}
      </div>
    {/if}
  </main>
</div>
