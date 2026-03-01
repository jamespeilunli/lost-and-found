<script lang="ts">
  import { onMount } from "svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";

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
      items = data as ItemRow[];
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
    if (!isLibrarian) {
      return;
    }

    const { error } = await supabase.from("items").delete().eq("id", itemId);

    if (error) {
      itemsError = error.message;
      return;
    }

    items = items.filter((item) => item.id !== itemId);
  }

  onMount(() => {
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

<div class="min-h-screen bg-gray-100">
  <header class="bg-white border-b border-gray-200">
    <div class="max-w-6xl mx-auto px-4 py-4 md:py-5">
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div class="text-left">
          <h1 class="text-left text-2xl md:text-3xl font-bold text-gray-800 leading-tight">Lost and Found</h1>
          <p class="text-sm text-gray-600 mt-1">Submit, track, and update community lost-and-found items.</p>
        </div>

        {#if session}
          <div class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4 md:justify-end">
            <div class="text-sm text-gray-600">
              Signed in as <strong>{session.user.email}</strong>
            </div>
            <span class="w-fit px-2 py-1 text-xs uppercase tracking-wide rounded-full bg-gray-100 text-gray-600">
              {userRole ?? "unknown"}
            </span>
            <button
              class="px-4 py-2 bg-gray-900 text-white rounded-lg hover:bg-gray-800 transition-colors"
              on:click={handleLogout}
              disabled={authLoading}
            >
              Log out
            </button>
          </div>
        {:else}
          <button
            class="w-full sm:w-auto px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors"
            on:click={handleGoogleSignIn}
            disabled={authLoading}
          >
            {authLoading ? "Redirecting..." : "Continue with Google"}
          </button>
        {/if}
      </div>

      {#if authError}
        <div class="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg">
          {authError}
        </div>
      {/if}
    </div>
  </header>

  <main class="max-w-6xl mx-auto px-4 py-6 space-y-6">
    <section class="bg-white border border-gray-200 p-6 md:p-8">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <h2 class="text-2xl font-bold text-gray-800">Items</h2>
        <div class="flex items-center gap-4">
          {#if session}
            <a href="/submit" class="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm hover:bg-indigo-700">
              Submit an Item
            </a>
          {:else}
            <button class="px-4 py-2 bg-gray-200 text-gray-500 rounded-lg text-sm cursor-not-allowed" disabled>
              Submit an Item
            </button>
          {/if}
          <button class="text-sm text-indigo-600 hover:text-indigo-800" on:click={loadItems} disabled={itemsLoading}>
            Refresh list
          </button>
        </div>
      </div>

      {#if itemsLoading}
        <p class="mt-4 text-gray-500">Loading items...</p>
      {:else if itemsError}
        <div class="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg">
          {itemsError}
        </div>
      {:else if items.length === 0}
        <p class="mt-4 text-gray-500 italic">No items yet. Submit the first entry.</p>
      {:else}
        <div class="mt-6 grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {#each items as item (item.id)}
            <article class="bg-white border border-gray-200 overflow-hidden flex flex-col">
              {#if item.image_url}
                <img src={item.image_url} alt={item.title} class="w-full h-44 object-cover" />
              {:else}
                <div class="w-full h-44 bg-gray-200 flex items-center justify-center text-gray-500 text-sm">
                  No image
                </div>
              {/if}
              <div class="p-4 space-y-3 flex-1">
                <div class="flex items-start justify-between gap-2">
                  <h3 class="text-lg font-semibold text-gray-800">{item.title}</h3>
                  <span class="px-2 py-1 text-xs font-semibold uppercase rounded-full bg-indigo-100 text-indigo-700">
                    {item.status}
                  </span>
                </div>
                <p class="text-sm text-gray-600">{item.description}</p>
                <div class="text-xs text-gray-500 space-y-1">
                  <div>Category: {item.category}</div>
                  {#if item.location_found}
                    <div>Location: {item.location_found}</div>
                  {/if}
                  <div>Created: {new Date(item.created_at).toLocaleString()}</div>
                </div>
              </div>
              {#if isLibrarian}
                <div class="border-t border-gray-200 p-4 bg-white space-y-2">
                  <span class="text-xs font-semibold text-gray-500">Librarian tools</span>
                  <div class="flex flex-wrap items-center gap-2">
                    <select
                      class="px-2 py-1 border border-gray-200 rounded-md text-sm"
                      value={item.status}
                      on:change={(event) =>
                        updateItemStatus(item.id, (event.target as HTMLSelectElement).value as ItemStatus)}
                    >
                      {#each statusOptions as option}
                        <option value={option}>{option}</option>
                      {/each}
                    </select>
                    <button
                      class="px-3 py-1 text-sm bg-red-600 text-white rounded-md hover:bg-red-700"
                      on:click={() => deleteItem(item.id)}
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
