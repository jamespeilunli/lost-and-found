<script lang="ts">
  import { onMount } from "svelte";
  import {
    Sun,
    Moon,
    Plus,
    Tag,
    MapPin,
    CalendarDays,
    EllipsisVertical,
    LogOut,
    Users,
    Search,
    LayoutGrid,
    TableProperties,
    RefreshCw,
    Info,
    Filter,
    ChevronDown,
    AlarmClock,
    Hourglass,
  } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { publicSupabase, supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Badge } from "$lib/components/ui/badge";
  import { Button } from "$lib/components/ui/button";
  import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "$lib/components/ui/card";
  import {
    DropdownMenu,
    DropdownMenuCheckboxGroup,
    DropdownMenuCheckboxItem,
    DropdownMenuContent,
    DropdownMenuRadioGroup,
    DropdownMenuRadioItem,
    DropdownMenuTrigger,
  } from "$lib/components/ui/dropdown-menu";
  import { Input } from "$lib/components/ui/input";
  import { Select, SelectContent, SelectItem, SelectTrigger } from "$lib/components/ui/select";
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
    manual_due_date: string | null;
  };

  const statusOptions: ItemStatus[] = ["found", "claimed"];
  const statusLabels: Record<ItemStatus, string> = {
    found: "At library",
    claimed: "Claimed",
  };
  const toolbarDropdownTriggerClass =
    "flex h-8 w-[176px] items-center justify-between gap-1.5 rounded-none border border-input bg-transparent py-2 pr-2 pl-2.5 text-xs whitespace-nowrap transition-colors outline-none select-none focus-visible:border-ring focus-visible:ring-1 focus-visible:ring-ring/50 aria-expanded:bg-muted [&_svg:not([class*='size-'])]:size-4 [&_svg]:pointer-events-none [&_svg]:shrink-0";
  const itemSelectColumns = "id,title,description,category,status,image_url,location_found,created_at,manual_due_date";

  let session: Session | null = null;
  let authLoading = false;
  let authError = "";

  let items: ItemRow[] = [];
  let itemsLoading = false;
  let itemsError = "";
  let deletedItems: ItemRow[] = [];
  let viewingDeleted = false;
  let searchQuery = "";
  let viewMode: ViewMode = "cards";
  let selectedStatusFilters: string[] = ["found"];
  let expandedTableDescriptions: Record<string, boolean> = {};
  let expandedCardDescriptions: Record<string, boolean> = {};
  let pendingItemId: string | null = null;
  let dueDateDrafts: Record<string, string> = {};
  let loadItemsRequestId = 0;
  $: isLibrarian = Boolean(session);

  // computed list to render (either normal items or deleted items)
  $: displayedItems = viewingDeleted ? deletedItems : items;
  $: filteredDisplayedItems = getFilteredItems(displayedItems, searchQuery, selectedStatusFilters);
  $: statusFilterSummary = getStatusFilterSummary(selectedStatusFilters);

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
  }

  function formatStatusLabel(status: ItemStatus) {
    return statusLabels[status];
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

  // --- Donation countdown ("sense of urgency") ---
  // The library donates all unclaimed items at the end of each month, so the
  // next clearing is the final moment of the current month.
  let now = new Date();

  // Items must sit at the library for a minimum grace period before they are
  // eligible for a month-end clearing, so something logged late in the month
  // rolls over to the next month's clearing rather than being donated days later.
  const GRACE_PERIOD_DAYS = 14;

  type UrgencyLevel = "normal" | "warning" | "critical";
  type Countdown = {
    totalMs: number;
    days: number;
    hours: number;
    minutes: number;
    seconds: number;
    level: UrgencyLevel;
  };

  function getNextClearingDate(reference: Date) {
    return new Date(reference.getFullYear(), reference.getMonth() + 1, 0, 23, 59, 59, 999);
  }

  // The earliest month-end clearing that occurs after the item has been at the
  // library for the full grace period.
  function getAutomaticDueDate(createdAt: string) {
    const eligibleFrom = new Date(createdAt);
    eligibleFrom.setDate(eligibleFrom.getDate() + GRACE_PERIOD_DAYS);
    return getNextClearingDate(eligibleFrom);
  }

  function parseManualDueDate(value: string | null) {
    if (!value) return null;
    const [year, month, day] = value.split("-").map(Number);
    if (!year || !month || !day) return null;
    return new Date(year, month - 1, day, 23, 59, 59, 999);
  }

  function getItemDonationDate(item: ItemRow) {
    return parseManualDueDate(item.manual_due_date) ?? getAutomaticDueDate(item.created_at);
  }

  function getCountdown(target: Date, current: Date): Countdown {
    const totalMs = Math.max(0, target.getTime() - current.getTime());
    const totalSeconds = Math.floor(totalMs / 1000);
    const days = Math.floor(totalSeconds / 86400);
    const hours = Math.floor((totalSeconds % 86400) / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    const level: UrgencyLevel = days <= 3 ? "critical" : days <= 7 ? "warning" : "normal";
    return { totalMs, days, hours, minutes, seconds, level };
  }

  function formatClearingDate(date: Date) {
    return date.toLocaleDateString(undefined, { month: "long", day: "numeric" });
  }

  function formatDueDate(date: Date) {
    return date.toLocaleDateString(undefined, { month: "long", day: "numeric", year: "numeric" });
  }

  function formatCountdown(c: Countdown) {
    if (c.days >= 1) {
      return `${c.days}d ${c.hours}h ${c.minutes}m`;
    }
    if (c.hours >= 1) {
      return `${c.hours}h ${c.minutes}m ${c.seconds}s`;
    }
    return `${c.minutes}m ${c.seconds}s`;
  }

  $: clearingDate = getNextClearingDate(now);
  $: clearingCountdown = getCountdown(clearingDate, now);

  const urgencyBannerClass: Record<UrgencyLevel, string> = {
    normal: "border-primary/40 bg-primary/10 text-foreground",
    warning: "border-amber-500/70 bg-amber-200 text-amber-950 dark:bg-amber-900/70 dark:text-amber-50",
    critical: "border-red-400/60 bg-red-100 text-red-950 dark:bg-red-950/60 dark:text-red-100",
  };

  const urgencyPillClass: Record<UrgencyLevel, string> = {
    normal: "bg-muted/55 text-muted-foreground",
    warning: "bg-amber-200 text-amber-950 dark:bg-amber-900 dark:text-amber-100",
    critical: "bg-red-100 text-red-900 dark:bg-red-950 dark:text-red-200",
  };

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
      { value: formatStatusLabel(item.status), weight: 1 },
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

  function getFilteredItems(list: ItemRow[], query: string, selectedStatuses: string[]) {
    const statusSet = new Set(selectedStatuses);
    const statusFilteredList = list.filter((item) => statusSet.has(item.status));
    const normalizedQuery = normalizeSearchValue(query);

    if (!normalizedQuery) {
      return statusFilteredList;
    }

    return statusFilteredList
      .map((item) => ({
        item,
        score: getItemSearchScore(item, normalizedQuery),
      }))
      .filter(({ score }) => score > 0)
      .sort((a, b) => b.score - a.score)
      .map(({ item }) => item);
  }

  function getStatusFilterSummary(selectedStatuses: string[]) {
    if (selectedStatuses.length === statusOptions.length) {
      return "All statuses";
    }

    if (selectedStatuses.length === 0) {
      return "No statuses";
    }

    return selectedStatuses.map((status) => formatStatusLabel(status as ItemStatus)).join(", ");
  }

  function shouldShowDescriptionToggle(description: string | null, maxLength: number) {
    return (description ?? "").trim().length > maxLength;
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
    if (!isLibrarian) return;
    viewingDeleted = nextValue;

    if (viewingDeleted) {
      await loadItems({ signedIn: true, showDeleted: true });
      return;
    }

    await loadItems({ signedIn: true, showDeleted: false });
  }

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    selectedStatusFilters = data.session ? [...statusOptions] : ["found"];
    return data.session;
  }

  function syncDueDateDrafts(list: ItemRow[]) {
    dueDateDrafts = Object.fromEntries(list.map((item) => [item.id, item.manual_due_date ?? ""]));
  }

  function isAuthorizationError(message: string) {
    const normalized = message.toLowerCase();
    return normalized.includes("row-level security") || normalized.includes("permission denied") || normalized.includes("librarian access");
  }

  async function loadItems(options: { signedIn?: boolean; showDeleted?: boolean } = {}) {
    const requestId = ++loadItemsRequestId;
    const signedIn = options.signedIn ?? isLibrarian;
    const showDeleted = signedIn && (options.showDeleted ?? viewingDeleted);
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
          .in("status", statusOptions)
          .order("created_at", { ascending: false })
      : publicSupabase
          .from("items")
          .select(itemSelectColumns)
          .eq("status", "found")
          .order("created_at", { ascending: false });

    const { data, error } = await query;

    if (requestId !== loadItemsRequestId) return;

    if (error) {
      itemsError = error.message;
      if (isAuthorizationError(error.message)) {
        authError = "This signed-in account is not approved for librarian tools.";
      }
      if (showDeleted) {
        deletedItems = [];
      } else {
        items = [];
      }
    } else {
      const fetchedItems = ((data ?? []) as ItemRow[]).sort(
        (a, b) => getItemDonationDate(a).getTime() - getItemDonationDate(b).getTime(),
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

  async function handleLogout() {
    authLoading = true;
    authError = "";
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

  async function updateItemStatus(itemId: string, nextStatus: ItemStatus) {
    if (!isLibrarian) {
      return;
    }

    const { data, error } = await supabase
      .from("items")
      .update({ status: nextStatus })
      .eq("id", itemId)
      .select(itemSelectColumns)
      .single();

    if (error) {
      itemsError = error.message;
      toast.error("Could not update item status: " + error.message);
      return;
    }

    items = items.map((item) => (item.id === itemId ? (data as ItemRow) : item));
    syncDueDateDrafts(items);
    toast.success(`Item marked as ${formatStatusLabel(nextStatus).toLowerCase()}.`);
  }

  async function updateItemDueDate(itemId: string) {
    if (!isLibrarian) return;

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
      itemsError = error.message;
      toast.error("Could not update pickup deadline: " + error.message);
      return;
    }

    items = items.map((item) => (item.id === itemId ? (data as ItemRow) : item));
    syncDueDateDrafts(items);
    toast.success(nextDueDate ? "Pickup deadline updated." : "Pickup deadline returned to automatic.");
  }

  async function deleteItem(itemId: string) {
    if (!isLibrarian) return;

    const item = items.find((i) => i.id === itemId);
    if (!item) return;

    try {
      pendingItemId = itemId;
      const toInsert = {
        id: item.id,
        title: item.title,
        description: item.description,
        category: item.category,
        status: item.status,
        image_url: item.image_url,
        location_found: item.location_found,
        created_at: item.created_at,
        created_by: session?.user.id ?? null,
        manual_due_date: item.manual_due_date,
      };

      const { error: insertError } = await supabase.from("deleted_items").insert([toInsert]);

      if (insertError) {
        pendingItemId = null;
        itemsError = insertError.message;
        toast.error("Failed to archive deleted item: " + insertError.message);
        return;
      }

      const { error } = await supabase.from("items").delete().eq("id", itemId);
      pendingItemId = null;

      if (error) {
        itemsError = error.message;
        toast.error("Deleted item was archived but removing the original failed: " + error.message);
        return;
      }

      items = items.filter((item) => item.id !== itemId);
      syncDueDateDrafts(items);

      toast.success("Item deleted and archived successfully.");
    } catch (err) {
      pendingItemId = null;
      itemsError = (err as Error).message;
      toast.error("An unexpected error occurred: " + (err as Error).message);
    }
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
      viewingDeleted = false;
      selectedStatusFilters = nextSession ? [...statusOptions] : ["found"];
      void loadItems({ signedIn: Boolean(nextSession), showDeleted: false });
    });

    const clockInterval = setInterval(() => {
      now = new Date();
    }, 1000);

    return () => {
      data.subscription.unsubscribe();
      clearInterval(clockInterval);
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
        <div class="flex items-center gap-3 text-left">
          {#if isDark}
            <img
              src="/faviconDark.png"
              alt="MVHS logo"
              class="h-12 w-12 shrink-0 object-contain md:h-14 md:w-14"
            />
          {:else}
            <img
              src="/favicon.png"
              alt="MVHS logo"
              class="h-12 w-12 shrink-0 object-contain md:h-14 md:w-14"
            />
          {/if}
          <div>
            <h1 class="text-left text-2xl font-bold leading-tight md:text-3xl">Library Lost &amp; Found</h1>
            <p class="mt-1 text-sm text-muted-foreground">Browse items currently at the library.</p>
          </div>
        </div>

        <div class="flex items-center gap-3 md:justify-end">
          {#if session}
            <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
              <div class="text-sm text-muted-foreground">
                Signed in as <strong>{session.user.email}</strong>
              </div>
              <Badge variant="outline" class="w-fit border-primary/40 text-sm uppercase tracking-wide">
                librarian
              </Badge>
            </div>
          {:else}
            <Button href="/sign-in" class="w-full text-sm sm:w-auto">
              Librarian sign in
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

                <a
                  href="/about"
                  role="menuitem"
                  class="flex w-full items-center gap-2 border-t border-border/80 px-3 py-2 text-left text-sm hover:bg-accent hover:text-accent-foreground"
                  onclick={closeMenu}
                >
                  <Info size={16} />
                  <span>About</span>
                </a>

                {#if session}
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
    <div
      class={`mb-6 flex flex-col gap-2 rounded-md border px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4 ${urgencyBannerClass[clearingCountdown.level]}`}
      role="status"
      aria-live="polite"
    >
      <div class="flex items-start gap-3">
        <AlarmClock size={20} class="mt-0.5 shrink-0" />
        <div>
          <p class="text-sm font-semibold">
            Next clearing: {formatClearingDate(clearingDate)}.
          </p>
          <p class="text-xs opacity-80">
            Items kept at least two weeks are donated at month-end. Check each item for its own pickup deadline.
          </p>
        </div>
      </div>
      <div class="flex shrink-0 items-center gap-2 sm:flex-col sm:items-end sm:gap-0.5">
        <span class="font-mono text-lg font-bold tabular-nums leading-none">
          {formatCountdown(clearingCountdown)}
        </span>
        <span class="text-[11px] font-medium uppercase tracking-wide opacity-80">until clearing</span>
      </div>
    </div>

    {#if isLibrarian}
      <Alert class="mb-6 border-primary/40 bg-primary/10 py-3 text-sm">
          <AlertTitle>Librarian View</AlertTitle>
          <AlertDescription>
          You can update statuses, adjust pickup deadlines, review archived records, and remove items.
        </AlertDescription>
      </Alert>
    {/if}

    <Card class="overflow-visible border-border/80 bg-card text-sm shadow-none">
      <CardHeader class="gap-3">
        <div class="flex flex-col gap-1 md:flex-row md:items-end md:justify-between">
          <div class="space-y-1">
            <CardTitle class="text-xl md:text-2xl">
              {viewingDeleted ? "Archived records" : "Library inventory"}
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
                  aria-label={viewingDeleted ? "Search archived items" : "Search inventory"}
                />
              </div>

              <div class="flex flex-wrap items-center gap-2 lg:shrink-0">
                <div>
                  <Button
                    variant="ghost"
                    size="icon"
                    class="size-10 border border-border/70 bg-background text-muted-foreground hover:text-foreground"
                    onclick={() => loadItems({ signedIn: isLibrarian, showDeleted: viewingDeleted })}
                    disabled={itemsLoading}
                    aria-label="Refresh items"
                    title="Refresh"
                  >
                    <RefreshCw size={16} class={itemsLoading ? "animate-spin" : ""} />
                  </Button>
                </div>
                {#if isLibrarian}
                  <Button href="/log-found" variant="secondary" class="gap-1.5 text-sm">
                    <Plus size={16} />
                    <span>Log found item</span>
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
                  <p class="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Status</p>
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      class={toolbarDropdownTriggerClass}
                      aria-label={`Filter by status, currently ${statusFilterSummary}`}
                    >
                      <span class="flex min-w-0 items-center gap-1.5">
                        <Filter class="text-muted-foreground" />
                        <span class="truncate">{statusFilterSummary}</span>
                      </span>
                      <ChevronDown class="text-muted-foreground" />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent>
                      <DropdownMenuCheckboxGroup bind:value={selectedStatusFilters}>
                        {#each (isLibrarian ? statusOptions : (["found"] as ItemStatus[])) as option}
                          <DropdownMenuCheckboxItem value={option} closeOnSelect={false}>
                            {formatStatusLabel(option)}
                          </DropdownMenuCheckboxItem>
                        {/each}
                      </DropdownMenuCheckboxGroup>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>

                <div class="space-y-1">
                  <p class="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Layout</p>
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      class={toolbarDropdownTriggerClass}
                      aria-label={`Choose layout, currently ${viewMode === "cards" ? "cards view" : "table view"}`}
                    >
                      <span class="flex min-w-0 items-center gap-1.5">
                        {#if viewMode === "cards"}
                          <LayoutGrid class="text-muted-foreground" />
                          <span>Cards</span>
                        {:else}
                          <TableProperties class="text-muted-foreground" />
                          <span>Table</span>
                        {/if}
                      </span>
                      <ChevronDown class="text-muted-foreground" />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent>
                      <DropdownMenuRadioGroup bind:value={viewMode}>
                        <DropdownMenuRadioItem value="cards">
                          <LayoutGrid />
                          <span>Cards</span>
                        </DropdownMenuRadioItem>
                        <DropdownMenuRadioItem value="table">
                          <TableProperties />
                          <span>Table</span>
                        </DropdownMenuRadioItem>
                      </DropdownMenuRadioGroup>
                    </DropdownMenuContent>
                  </DropdownMenu>
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
          <p class="italic text-muted-foreground">No items match the current view.</p>
        {:else if filteredDisplayedItems.length === 0}
          <p class="italic text-muted-foreground">No items match the current filters.</p>
        {:else}
          {#if viewMode === "cards"}
            <div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-3">
              {#each filteredDisplayedItems as item (item.id)}
                {@const showItemActions = !viewingDeleted && isLibrarian}
                <Card class="border-border/80 bg-card py-0">
                  {#if item.image_url}
                    <img src={item.image_url} alt={item.title} class="h-[clamp(16rem,28vw,20rem)] w-full object-cover" />
                  {:else}
                    <div class="flex h-[clamp(16rem,28vw,20rem)] w-full items-center justify-center bg-muted text-sm text-muted-foreground">
                      No image
                    </div>
                  {/if}

                  <CardContent class={`border-border/80 flex-1 space-y-4 ${showItemActions ? "" : "pb-4"}`}>
                    <div class="flex items-start justify-between gap-3">
                      <h3 class="text-base font-semibold md:text-lg">{item.title}</h3>
                      <Badge class={`${statusBadgeVariant(item.status)} text-sm`}>
                        {formatStatusLabel(item.status)}
                      </Badge>
                    </div>
                    <div>
                      <p class={`text-sm text-muted-foreground ${expandedCardDescriptions[item.id] ? "" : "line-clamp-4"}`}>
                        {item.description || "No description provided."}
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
                      {#if !viewingDeleted && item.status === "found"}
                        {@const itemDonationDate = getItemDonationDate(item)}
                        {@const itemCountdown = getCountdown(itemDonationDate, now)}
                        <div
                          class={`inline-flex max-w-full items-center gap-2 rounded-full px-2.5 py-1.5 font-medium ${urgencyPillClass[itemCountdown.level]}`}
                          title={`Donated on ${formatClearingDate(itemDonationDate)} if not picked up`}
                          aria-label={`${formatCountdown(itemCountdown)} until this item is donated`}
                        >
                          <Hourglass size={15} class="shrink-0" />
                          <span class="tabular-nums">{formatCountdown(itemCountdown)} left</span>
                        </div>
                        {#if isLibrarian}
                          <div class="inline-flex max-w-full items-center gap-2 rounded-full bg-muted/55 px-2.5 py-1.5">
                            <CalendarDays size={15} class="shrink-0 text-primary" />
                            <span>Due {formatDueDate(itemDonationDate)}</span>
                          </div>
                        {/if}
                      {/if}
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
                    {#if isLibrarian && !viewingDeleted && item.status === "found"}
                      <div class="flex flex-col gap-2 border-t border-border/80 pt-4 sm:flex-row sm:items-end">
                        <div class="min-w-0 flex-1 space-y-1">
                          <p class="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Pickup deadline override</p>
                          <Input type="date" class="h-9 bg-background text-sm" bind:value={dueDateDrafts[item.id]} />
                        </div>
                        <Button
                          variant="outline"
                          size="sm"
                          class="text-sm"
                          onclick={() => updateItemDueDate(item.id)}
                          disabled={pendingItemId === item.id}
                        >
                          Save date
                        </Button>
                      </div>
                    {/if}
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
                              {formatStatusLabel(item.status)}
                            </SelectTrigger>
                            <SelectContent>
                              {#each statusOptions as option}
                                <SelectItem value={option} label={formatStatusLabel(option)} />
                              {/each}
                            </SelectContent>
                          </Select>
                        {/if}
                        <Button href={`/edit/${item.id}`} variant="outline" size="sm" class="text-sm">Edit</Button>
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
                  <col class="w-[34%]" />
                  <col class="w-[10%]" />
                  <col class="w-[10%]" />
                  <col class="w-[12%]" />
                  <col class="w-[12%]" />
                  <col class="w-[13%]" />
                  {#if isLibrarian}
                    <col class="w-[13%]" />
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
                    <th class="px-4 py-3 font-medium">Until donation</th>
                    {#if isLibrarian}
                      <th class="px-4 py-3 font-medium">Pickup deadline</th>
                    {/if}
                    <th class="px-4 py-3 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {#each filteredDisplayedItems as item (item.id)}
                    {@const showItemActions =
                      !viewingDeleted && isLibrarian}
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
                                {item.description || "No description provided."}
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
                          {formatStatusLabel(item.status)}
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
                      <td class="px-4 py-4 whitespace-nowrap">
                        {#if !viewingDeleted && item.status === "found"}
                          {@const itemDonationDate = getItemDonationDate(item)}
                          {@const itemCountdown = getCountdown(itemDonationDate, now)}
                          <div
                            class={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ${urgencyPillClass[itemCountdown.level]}`}
                            title={`Donated on ${formatClearingDate(itemDonationDate)} if not picked up`}
                          >
                            <Hourglass size={12} class="shrink-0" />
                            <span class="tabular-nums">{formatCountdown(itemCountdown)}</span>
                          </div>
                        {:else}
                          <span class="text-muted-foreground">—</span>
                        {/if}
                      </td>
                      {#if isLibrarian}
                        <td class="px-4 py-4">
                          {#if !viewingDeleted && item.status === "found"}
                            <div class="flex min-w-[220px] items-center gap-2">
                              <Input type="date" class="h-8 bg-background text-xs" bind:value={dueDateDrafts[item.id]} />
                              <Button
                                variant="outline"
                                size="sm"
                                class="text-xs"
                                onclick={() => updateItemDueDate(item.id)}
                                disabled={pendingItemId === item.id}
                              >
                                Save
                              </Button>
                            </div>
                          {:else}
                            <span class="text-muted-foreground">Automatic</span>
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
                                      {formatStatusLabel(item.status)}
                                    </SelectTrigger>
                                    <SelectContent>
                                      {#each statusOptions as option}
                                        <SelectItem value={option} label={formatStatusLabel(option)} />
                                      {/each}
                                    </SelectContent>
                                  </Select>
                                </div>
                              {/if}
                              <div class="mt-2 flex flex-col gap-1">
                                <Button href={`/edit/${item.id}`} variant="outline" size="sm" class="justify-start text-sm">Edit item</Button>
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
