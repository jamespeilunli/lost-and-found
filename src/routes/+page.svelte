<script lang="ts">
  import { onMount } from "svelte";
  import { Sun, Moon } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";

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

    const { data, error } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .maybeSingle();

    if (error) {
      userRole = null;
      return;
    }

    userRole = (data?.role as UserRole | null) ?? "user";
  }

  async function loadItems() {
    itemsLoading = true;
    itemsError = "";

    const { data, error } = await supabase
      .from("items")
      .select("*")
      .order("created_at", { ascending: false });

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

    const redirectTo =
      typeof window !== "undefined" ? `${window.location.origin}` : undefined;
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

    items = items.map((item) =>
      item.id === itemId ? (data as ItemRow) : item,
    );
  }

  async function deleteItem(itemId: string) {
    const item = items.find((i) => i.id === itemId);
    const isOwner = session?.user?.id === item?.created_by;

    if (!isLibrarian && !isOwner) {
      return;
    }

    const { data, error } = await supabase
      .from("items")
      .delete()
      .eq("id", itemId)
      .select();

    if (error) {
      itemsError = error.message;
      return;
    }

    if (!data || data.length === 0) {
      alert(
        "Failed to delete item. You may lack permission, or Row Level Security (RLS) is blocking the action.",
      );
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

<div
  class="min-h-screen bg-gray-100 dark:bg-[#181a1b] transition-colors duration-200"
>
  <header
    class="bg-white dark:bg-[#181a1b] border-b border-gray-200 dark:border-[#736b5e] transition-colors duration-200"
  >
    <div class="max-w-6xl mx-auto px-4 py-4 md:py-5">
      <div
        class="flex flex-col md:flex-row md:items-center md:justify-between gap-4"
      >
        <div class="text-left">
          <h1
            class="text-left text-2xl md:text-3xl font-bold text-gray-800 dark:text-[#e8e6e3] leading-tight"
          >
            Lost and Found
          </h1>
          <p class="text-sm text-gray-600 dark:text-[#b2aba1] mt-1">
            Submit, track, and update community lost-and-found items.
          </p>
        </div>

        <div class="flex items-center gap-3">
          <button
            class="p-2 rounded-lg bg-gray-100 dark:bg-[#181a1b] text-gray-600 dark:text-[#b2aba1] hover:bg-gray-200 dark:hover:bg-[#2a2c2d] transition-colors"
            on:click={toggleTheme}
            aria-label="Toggle dark mode"
          >
            {#if isDark}
              <Sun size={20} />
            {:else}
              <Moon size={20} />
            {/if}
          </button>

          {#if session}
            <div
              class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4 md:justify-end"
            >
              <div class="text-sm text-gray-600 dark:text-[#b2aba1]">
                Signed in as <strong>{session.user.email}</strong>
              </div>
              <span
                class="w-fit px-2 py-1 text-xs uppercase tracking-wide rounded-full bg-gray-100 dark:bg-[#181a1b] text-gray-600 dark:text-[#b2aba1]"
              >
                {userRole ?? "unknown"}
              </span>
              <button
                class="px-4 py-2 bg-gray-900 dark:bg-gray-100 text-white dark:text-gray-900 rounded-lg hover:bg-gray-800 dark:hover:bg-gray-200 transition-colors"
                on:click={handleLogout}
                disabled={authLoading}
              >
                Log out
              </button>
            </div>
          {:else}
            <button
              class="w-full sm:w-auto px-4 py-2 bg-yellow-400 dark:bg-yellow-500 text-black font-medium rounded-lg hover:bg-yellow-500 dark:hover:bg-yellow-400 transition-colors"
              on:click={handleGoogleSignIn}
              disabled={authLoading}
            >
              {authLoading ? "Redirecting..." : "Continue with Google"}
            </button>
          {/if}
        </div>
      </div>

      {#if authError}
        <div
          class="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg"
        >
          {authError}
        </div>
      {/if}
    </div>
  </header>

  <main class="max-w-6xl mx-auto px-4 py-6 space-y-6">
    <section
      class="bg-white dark:bg-[#181a1b] border border-gray-200 dark:border-[#736b5e] p-6 md:p-8 rounded-lg transition-colors duration-200"
    >
      <div class="flex items-center justify-between flex-wrap gap-2">
        <h2 class="text-2xl font-bold text-gray-800 dark:text-[#e8e6e3]">
          Items
        </h2>
        <div class="flex items-center gap-4">
          {#if session}
            <a
              href="/submit"
              class="px-4 py-2 bg-yellow-400 dark:bg-yellow-500 text-black font-medium rounded-lg text-sm hover:bg-yellow-500 dark:hover:bg-yellow-400 transition-colors"
            >
              Submit an Item
            </a>
          {:else}
            <button
              class="px-4 py-2 bg-gray-200 dark:bg-[#181a1b] text-gray-500 dark:text-[#b2aba1] rounded-lg text-sm cursor-not-allowed transition-colors"
              disabled
            >
              Submit an Item
            </button>
          {/if}
          <button
            class="text-sm text-yellow-600 dark:text-yellow-400 hover:text-yellow-800 dark:hover:text-yellow-300 transition-colors font-medium"
            on:click={loadItems}
            disabled={itemsLoading}
          >
            Refresh list
          </button>
        </div>
      </div>

      {#if itemsLoading}
        <p class="mt-4 text-gray-500 dark:text-[#b2aba1]">Loading items...</p>
      {:else if itemsError}
        <div
          class="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg"
        >
          {itemsError}
        </div>
      {:else if items.length === 0}
        <p class="mt-4 text-gray-500 dark:text-[#b2aba1] italic">
          No items yet. Submit the first entry.
        </p>
      {:else}
        <div class="mt-6 grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {#each items as item (item.id)}
            <article
              class="bg-white dark:bg-[#181a1b] border border-gray-200 dark:border-[#736b5e] overflow-hidden flex flex-col rounded-lg transition-colors duration-200"
            >
              {#if item.image_url}
                <img
                  src={item.image_url}
                  alt={item.title}
                  class="w-full h-44 object-cover"
                />
              {:else}
                <div
                  class="w-full h-44 bg-gray-200 dark:bg-[#181a1b] flex items-center justify-center text-gray-500 dark:text-[#b2aba1] text-sm transition-colors duration-200"
                >
                  No image
                </div>
              {/if}
              <div class="p-4 space-y-3 flex-1">
                <div class="flex items-start justify-between gap-2">
                  <h3
                    class="text-lg font-semibold text-gray-800 dark:text-[#e8e6e3]"
                  >
                    {item.title}
                  </h3>
                  <span
                    class="px-2 py-1 text-xs font-semibold uppercase rounded-full {item.status ===
                    'found'
                      ? 'bg-green-100 dark:bg-green-900/40 text-green-700 dark:text-green-400'
                      : item.status === 'claimed'
                        ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-400'
                        : 'bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-400'}"
                  >
                    {item.status}
                  </span>
                </div>
                <p class="text-sm text-gray-600 dark:text-[#b2aba1]">
                  {item.description}
                </p>
                <div
                  class="text-xs text-gray-500 dark:text-[#b2aba1] space-y-1"
                >
                  <div>Category: {item.category}</div>
                  {#if item.location_found}
                    <div>Location: {item.location_found}</div>
                  {/if}
                  <div>
                    Created: {new Date(item.created_at).toLocaleString()}
                  </div>
                </div>
              </div>
              {#if isLibrarian || (session && session.user.id === item.created_by)}
                <div
                  class="border-t border-gray-200 dark:border-[#736b5e] p-4 bg-white dark:bg-[#181a1b] transition-colors duration-200"
                >
                  <div class="flex items-center justify-between w-full gap-2">
                    <div class="flex items-center gap-2">
                      {#if isLibrarian}
                        <select
                          class="py-1.5 pl-3 pr-8 border border-gray-200 dark:border-[#545b5e] rounded-md text-sm bg-white dark:bg-[#181a1b] text-gray-800 dark:text-[#e8e6e3] transition-colors"
                          value={item.status}
                          on:change={(event) =>
                            updateItemStatus(
                              item.id,
                              (event.target as HTMLSelectElement)
                                .value as ItemStatus,
                            )}
                        >
                          {#each statusOptions as option}
                            <option value={option}>{option}</option>
                          {/each}
                        </select>
                      {/if}
                      {#if session && session.user.id === item.created_by}
                        <a
                          href="/edit/{item.id}"
                          class="px-3 py-1 text-sm bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-400 rounded-md hover:bg-yellow-200 dark:hover:bg-yellow-900/60 transition-colors font-medium"
                        >
                          Edit
                        </a>
                      {/if}
                    </div>
                    <button
                      class="px-3 py-1 text-sm bg-red-600 dark:bg-red-500/80 text-white rounded-md hover:bg-red-700 dark:hover:bg-red-500 transition-colors"
                      on:click={() => {
                        if (
                          confirm("Are you sure you want to delete this item?")
                        ) {
                          deleteItem(item.id);
                        }
                      }}
                    >
                      Delete
                    </button>
                  </div>
                </div>
              {/if}
            </article>
          {/each}
        </div>
      {/if}
    </section>
  </main>
</div>
