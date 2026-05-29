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

  type ItemStatus = "lost" | "found" | "claimed";
  type UserRole = "librarian";
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
    created_by?: string;
    manual_due_date: string | null;
  };

  const activeStatusOptions: ItemStatus[] = ["found", "claimed"];
  const statusLabels: Record<ItemStatus, string> = {
    lost: "Removed",
    found: "At library",
    claimed: "Claimed",
  };
  const toolbarDropdownTriggerClass =
    "flex h-8 w-[176px] items-center justify-between gap-1.5 rounded-none border border-input bg-transparent py-2 pr-2 pl-2.5 text-xs whitespace-nowrap transition-colors outline-none select-none focus-visible:border-ring focus-visible:ring-1 focus-visible:ring-ring/50 aria-expanded:bg-muted [&_svg:not([class*='size-'])]:size-4 [&_svg]:pointer-events-none [&_svg]:shrink-0";
  const itemSelectColumns = "id,title,description,category,status,image_url,location_found,created_at,manual_due_date";

  let session: Session | null = null;
  let userRole: UserRole | null = null;
  let authLoading = false;
  let authError = "";
  let isLoggingOut = false;

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
  $: isLibrarian = userRole === "librarian";

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

    return "bg-primary/20 text-foreground uppercase dark:bg-primary/25";
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

  function parseManualDueDate(value: string) {
    const [year, month, day] = value.split("-").map(Number);
    if (!year || !month || !day) return null;
    return new Date(year, month - 1, day, 23, 59, 59, 999);
  }

  function getEffectiveDueDate(item: ItemRow) {
    return item.manual_due_date
      ? (parseManualDueDate(item.manual_due_date) ?? getAutomaticDueDate(item.created_at))
      : getAutomaticDueDate(item.created_at);
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
    if (selectedStatuses.length === activeStatusOptions.length) {
      return "All statuses";
    }

    if (selectedStatuses.length === 0) {
      return "No statuses";
    }

    return selectedStatuses.map((status) => formatStatusLabel(status as ItemStatus)).join(", ");
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

  function clearLocalSupabaseSession() {
    if (typeof window === "undefined") return;

    for (let index = window.localStorage.length - 1; index >= 0; index -= 1) {
      const key = window.localStorage.key(index);
      if (key && (key === "supabase.auth.token" || (key.startsWith("sb-") && key.endsWith("-auth-token")))) {
        window.localStorage.removeItem(key);
      }
    }
  }

  async function setViewingDeleted(nextValue: boolean) {
    if (!isLibrarian) return;
    viewingDeleted = nextValue;
    await loadItems({ librarian: true, showDeleted: nextValue });
  }

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    return await loadUserRole(data.session);
  }

  async function loadUserRole(nextSession: Session | null) {
    if (!nextSession?.user) {
      userRole = null;
      return null;
    }

    const { data, error } = await supabase.rpc("is_librarian_email");
    if (error || data !== true) {
      session = null;
      userRole = null;
      authError = "This Google account is not on the librarian whitelist.";
      await supabase.auth.signOut({ scope: "local" });
      clearLocalSupabaseSession();
      return null;
    }

    userRole = "librarian";
    authError = "";
    selectedStatusFilters = [...activeStatusOptions];
    return userRole;
  }

  function syncDueDateDrafts(list: ItemRow[]) {
    dueDateDrafts = Object.fromEntries(list.map((item) => [item.id, item.manual_due_date ?? ""]));
  }

  async function loadItems(options: { librarian?: boolean; showDeleted?: boolean } = {}) {
    const requestId = ++loadItemsRequestId;
    const librarian = options.librarian ?? userRole === "librarian";
    const showDeleted = librarian && (options.showDeleted ?? viewingDeleted);

    if (!librarian) {
      viewingDeleted = false;
      deletedItems = [];
      selectedStatusFilters = ["found"];
    }

    itemsLoading = true;
    itemsError = "";

    const query = librarian
      ? supabase
          .from(showDeleted ? "deleted_items" : "items")
          .select(itemSelectColumns)
          .in("status", activeStatusOptions)
          .order("created_at", { ascending: false })
      : publicSupabase
          .from("items")
          .select(itemSelectColumns)
          .eq("status", "found")
          .order("created_at", { ascending: false });

    const { data, error } = await query;

    if (requestId !== loadItemsRequestId) {
      return;
    }

    if (error) {
      itemsError = error.message;
      if (showDeleted) {
        deletedItems = [];
      } else {
        items = [];
      }
    } else {
      const fetchedItems = ((data ?? []) as ItemRow[]).sort((a, b) => {
        if (a.status === "found" && b.status !== "found") return -1;
        if (a.status !== "found" && b.status === "found") return 1;
        return getEffectiveDueDate(a).getTime() - getEffectiveDueDate(b).getTime();
      });

      if (showDeleted) {
        deletedItems = fetchedItems;
      } else {
        items = fetchedItems;
      }
      syncDueDateDrafts(fetchedItems);
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
    isLoggingOut = true;
    menuOpen = false;

    session = null;
    userRole = null;
    viewingDeleted = false;
    deletedItems = [];
    selectedStatusFilters = ["found"];

    const { error } = await supabase.auth.signOut({ scope: "local" });
    clearLocalSupabaseSession();
    if (error) {
      authError = error.message;
    }
    await loadItems({ librarian: false, showDeleted: false });

    isLoggingOut = false;
    authLoading = false;
  }

  async function updateItemStatus(itemId: string, nextStatus: ItemStatus) {
    if (!isLibrarian || nextStatus === "lost") {
      return;
    }

    pendingItemId = itemId;
    const { data, error } = await supabase
      .from("items")
      .update({ status: nextStatus })
      .eq("id", itemId)
      .select(itemSelectColumns)
      .single();
    pendingItemId = null;

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
      toast.error("Could not update due date: " + error.message);
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
        created_by: item.created_by,
        manual_due_date: item.manual_due_date,
      };

      const { error: insertError } = await supabase.from("deleted_items").insert([toInsert]);

      if (insertError) {
        pendingItemId = null;
        itemsError = insertError.message;
        toast.error("Failed to archive item: " + insertError.message);
        return;
      }

      const { error } = await supabase.from("items").delete().eq("id", itemId);
      pendingItemId = null;

      if (error) {
        itemsError = error.message;
        toast.error("Archived item, but removing the active row failed: " + error.message);
        return;
      }

      items = items.filter((item) => item.id !== itemId);
      syncDueDateDrafts(items);

      toast.success("Item archived.");
    } catch (err) {
      pendingItemId = null;
      itemsError = (err as Error).message;
      toast.error("An unexpected error occurred: " + (err as Error).message);
    }
  }

  onMount(() => {
    isDark = document.documentElement.classList.contains("dark");

    void (async () => {
      const role = await loadSession();
      await loadItems({ librarian: role === "librarian", showDeleted: false });
    })();

    const { data } = supabase.auth.onAuthStateChange(async (_event, nextSession) => {
      if (isLoggingOut) {
        session = null;
        userRole = null;
        viewingDeleted = false;
        return;
      }

      session = nextSession;
      const role = await loadUserRole(nextSession);
      viewingDeleted = false;
      await loadItems({ librarian: role === "librarian", showDeleted: false });
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
            <img src="/faviconDark.png" alt="MVHS logo" class="h-12 w-12 shrink-0 object-contain md:h-14 md:w-14" />
          {:else}
            <img src="/favicon.png" alt="MVHS logo" class="h-12 w-12 shrink-0 object-contain md:h-14 md:w-14" />
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
                {userRole ?? "unknown"}
              </Badge>
            </div>
          {:else}
            <Button class="w-full text-sm sm:w-auto" onclick={handleGoogleSignIn} disabled={authLoading}>
              {authLoading ? "Redirecting..." : "Librarian sign in"}
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
          You can log items, update statuses, set pickup deadlines, and review archived records.
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
                  placeholder={viewingDeleted
                    ? "Search archived items"
                    : "Search by title, category, location, or description"}
                  aria-label={viewingDeleted ? "Search archived items" : "Search inventory"}
                />
              </div>

              <div class="flex flex-wrap items-center gap-2 lg:shrink-0">
                <div>
                  <Button
                    variant="ghost"
                    size="icon"
                    class="size-10 border border-border/70 bg-background text-muted-foreground hover:text-foreground"
                    onclick={loadItems}
                    disabled={itemsLoading}
                    aria-label="Refresh items"
                    title="Refresh"
                  >
                    <RefreshCw size={16} class={itemsLoading ? "animate-spin" : ""} />
                  </Button>
                </div>
                {#if isLibrarian}
                  <Button href="/log-found" class="gap-1.5 text-sm">
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
                        {#each activeStatusOptions as option}
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
            <p class="italic text-muted-foreground">
              {viewingDeleted ? "No archived records to show." : "No inventory records to show."}
            </p>
          {:else if filteredDisplayedItems.length === 0}
            <p class="italic text-muted-foreground">No items match the current filters.</p>
          {:else if viewMode === "cards"}
            <div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-3">
              {#each filteredDisplayedItems as item (item.id)}
                {@const showItemActions = !viewingDeleted && isLibrarian}
                <Card class="border-border/80 bg-card py-0">
                  {#if item.image_url}
                    <img
                      src={item.image_url}
                      alt={item.title}
                      class="h-[clamp(16rem,28vw,20rem)] w-full object-cover"
                    />
                  {:else}
                    <div
                      class="flex h-[clamp(16rem,28vw,20rem)] w-full items-center justify-center bg-muted text-sm text-muted-foreground"
                    >
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
                      <p
                        class={`text-sm text-muted-foreground ${expandedCardDescriptions[item.id] ? "" : "line-clamp-4"}`}
                      >
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
                      {#if !viewingDeleted && item.status === "found"}
                        {@const itemDonationDate = getEffectiveDueDate(item)}
                        {@const itemCountdown = getCountdown(itemDonationDate, now)}
                        <div
                          class={`inline-flex max-w-full items-center gap-2 rounded-full px-2.5 py-1.5 font-medium ${urgencyPillClass[itemCountdown.level]}`}
                          title={`${item.manual_due_date ? "Custom" : "Automatic"} pickup deadline: ${formatDueDate(itemDonationDate)}`}
                          aria-label={`${formatCountdown(itemCountdown)} until this item is donated`}
                        >
                          <Hourglass size={15} class="shrink-0" />
                          <span class="tabular-nums">{formatCountdown(itemCountdown)} left</span>
                          <span class="text-[10px] uppercase opacity-70"
                            >{item.manual_due_date ? "custom" : "auto"}</span
                          >
                        </div>
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
                  </CardContent>

                  {#if showItemActions}
                    <CardFooter class="border-border/80 flex flex-col items-stretch gap-3 bg-card px-4 py-4">
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
                              {#each activeStatusOptions as option}
                                <SelectItem value={option} label={formatStatusLabel(option)} />
                              {/each}
                            </SelectContent>
                          </Select>
                        {/if}
                        <Button href="/edit/{item.id}" variant="outline" size="sm" class="text-sm">Edit</Button>
                        <Button
                          variant="destructive"
                          size="sm"
                          class="text-sm"
                          disabled={pendingItemId === item.id}
                          onclick={() => {
                            if (confirm("Archive and remove this item from the public list?")) {
                              deleteItem(item.id);
                            }
                          }}
                        >
                          Archive item
                        </Button>
                      </div>
                      {#if item.status === "found"}
                        <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
                          <Input
                            type="date"
                            class="h-9 bg-background text-sm sm:w-44"
                            bind:value={dueDateDrafts[item.id]}
                            aria-label={`Pickup deadline for ${item.title}`}
                          />
                          <div class="flex gap-2">
                            <Button
                              variant="outline"
                              size="sm"
                              class="text-sm"
                              disabled={pendingItemId === item.id ||
                                dueDateDrafts[item.id] === (item.manual_due_date ?? "")}
                              onclick={() => updateItemDueDate(item.id)}
                            >
                              Save deadline
                            </Button>
                            {#if item.manual_due_date}
                              <Button
                                variant="ghost"
                                size="sm"
                                class="text-sm"
                                disabled={pendingItemId === item.id}
                                onclick={() => {
                                  dueDateDrafts[item.id] = "";
                                  updateItemDueDate(item.id);
                                }}
                              >
                                Use auto
                              </Button>
                            {/if}
                          </div>
                        </div>
                      {/if}
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
                    <col class="w-[19%]" />
                    <col class="w-[10%]" />
                  {/if}
                </colgroup>
                <thead class="bg-muted/40 text-muted-foreground">
                  <tr>
                    <th class="px-4 py-3 font-medium">Item</th>
                    <th class="px-4 py-3 font-medium">Status</th>
                    <th class="px-4 py-3 font-medium">Category</th>
                    <th class="px-4 py-3 font-medium">Location</th>
                    <th class="px-4 py-3 font-medium">Logged</th>
                    <th class="px-4 py-3 font-medium">Until donation</th>
                    {#if isLibrarian}
                      <th class="px-4 py-3 font-medium">Pickup deadline</th>
                      <th class="px-4 py-3 font-medium">Actions</th>
                    {/if}
                  </tr>
                </thead>
                <tbody>
                  {#each filteredDisplayedItems as item (item.id)}
                    {@const showItemActions = !viewingDeleted && isLibrarian}
                    <tr class="border-t border-border/80 align-top">
                      <td class="px-4 py-4">
                        <div class="flex items-start gap-3">
                          {#if item.image_url}
                            <img
                              src={item.image_url}
                              alt={item.title}
                              class="h-12 w-12 rounded-sm object-cover shrink-0"
                            />
                          {:else}
                            <div
                              class="flex h-12 w-12 items-center justify-center rounded-sm bg-muted text-xs text-muted-foreground shrink-0"
                            >
                              None
                            </div>
                          {/if}
                          <div class="min-w-0 flex-1 space-y-1">
                            <div class="truncate pr-2 font-medium">{item.title}</div>
                            <div class="max-w-none">
                              <p
                                class={`text-muted-foreground ${expandedTableDescriptions[item.id] ? "" : "line-clamp-2"}`}
                              >
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
                          <span class="block truncate" title={item.location_found ?? "Unknown"}
                            >{item.location_found ?? "Unknown"}</span
                          >
                        </div>
                      </td>
                      <td class="px-4 py-4 whitespace-nowrap">
                        <div class="w-full">
                          <span class="block truncate" title={formatItemDate(item.created_at)}
                            >{formatItemDate(item.created_at)}</span
                          >
                        </div>
                      </td>
                      <td class="px-4 py-4 whitespace-nowrap">
                        {#if !viewingDeleted && item.status === "found"}
                          {@const itemDonationDate = getEffectiveDueDate(item)}
                          {@const itemCountdown = getCountdown(itemDonationDate, now)}
                          <div
                            class={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ${urgencyPillClass[itemCountdown.level]}`}
                            title={`${item.manual_due_date ? "Custom" : "Automatic"} pickup deadline: ${formatDueDate(itemDonationDate)}`}
                          >
                            <Hourglass size={12} class="shrink-0" />
                            <span class="tabular-nums">{formatCountdown(itemCountdown)}</span>
                            <span class="uppercase opacity-70">{item.manual_due_date ? "custom" : "auto"}</span>
                          </div>
                        {:else}
                          <span class="text-muted-foreground">—</span>
                        {/if}
                      </td>
                      {#if isLibrarian}
                        <td class="px-4 py-4">
                          {#if !viewingDeleted && item.status === "found"}
                            <div class="flex min-w-44 flex-col gap-2">
                              <Input
                                type="date"
                                class="h-8 bg-background text-xs"
                                bind:value={dueDateDrafts[item.id]}
                                aria-label={`Pickup deadline for ${item.title}`}
                              />
                              <div class="flex gap-1">
                                <Button
                                  variant="outline"
                                  size="sm"
                                  class="h-7 px-2 text-xs"
                                  disabled={pendingItemId === item.id ||
                                    dueDateDrafts[item.id] === (item.manual_due_date ?? "")}
                                  onclick={() => updateItemDueDate(item.id)}
                                >
                                  Save
                                </Button>
                                {#if item.manual_due_date}
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    class="h-7 px-2 text-xs"
                                    disabled={pendingItemId === item.id}
                                    onclick={() => {
                                      dueDateDrafts[item.id] = "";
                                      updateItemDueDate(item.id);
                                    }}
                                  >
                                    Auto
                                  </Button>
                                {/if}
                              </div>
                            </div>
                          {:else}
                            <span class="text-muted-foreground">—</span>
                          {/if}
                        </td>
                        <td class="px-4 py-4">
                          {#if showItemActions}
                            <details class="relative">
                              <summary
                                class="flex h-8 w-8 cursor-pointer list-none items-center justify-center rounded-sm border border-border/80 bg-background text-muted-foreground hover:bg-muted [&::-webkit-details-marker]:hidden"
                                aria-label={`Open actions for ${item.title}`}
                              >
                                <EllipsisVertical size={16} />
                              </summary>
                              <div
                                class="absolute right-0 top-10 z-20 w-56 rounded-md border border-border/80 bg-popover p-2 shadow-md"
                              >
                                <div class="space-y-1">
                                  <p
                                    class="px-2 pt-1 text-xs font-medium uppercase tracking-wide text-muted-foreground"
                                  >
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
                                      {#each activeStatusOptions as option}
                                        <SelectItem value={option} label={formatStatusLabel(option)} />
                                      {/each}
                                    </SelectContent>
                                  </Select>
                                </div>
                                <div class="mt-2 flex flex-col gap-1">
                                  <Button
                                    href="/edit/{item.id}"
                                    variant="outline"
                                    size="sm"
                                    class="justify-start text-sm">Edit item</Button
                                  >
                                  <Button
                                    variant="destructive"
                                    size="sm"
                                    class="justify-start text-sm"
                                    disabled={pendingItemId === item.id}
                                    onclick={() => {
                                      if (confirm("Archive and remove this item from the public list?")) {
                                        deleteItem(item.id);
                                      }
                                    }}
                                  >
                                    Archive item
                                  </Button>
                                </div>
                              </div>
                            </details>
                          {:else}
                            <span class="text-muted-foreground">No actions</span>
                          {/if}
                        </td>
                      {/if}
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          {/if}
        </div>
      </CardContent>
    </Card>
  </main>
</div>
