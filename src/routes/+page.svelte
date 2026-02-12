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
  let email = "";
  let password = "";
  let isSigningUp = false;

  let items: ItemRow[] = [];
  let itemsLoading = false;
  let itemsError = "";

  let title = "";
  let description = "";
  let category = "";
  const defaultStatus: ItemStatus = "lost";
  const imageBucket = "item-images";

  let imageFile: File | null = null;
  let imageInput: HTMLInputElement | null = null;
  let locationFound = "";
  let formError = "";
  let formLoading = false;
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

  async function handleAuthSubmit() {
    authLoading = true;
    authError = "";

    if (!email.trim() || !password.trim()) {
      authLoading = false;
      authError = "Email and password are required.";
      return;
    }

    const credentials = { email: email.trim(), password };
    const { error } = isSigningUp
      ? await supabase.auth.signUp(credentials)
      : await supabase.auth.signInWithPassword(credentials);

    if (error) {
      authError = error.message;
    } else {
      email = "";
      password = "";
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

  async function handleSubmitItem() {
    if (!session?.user) {
      formError = "Please sign in to submit an item.";
      return;
    }

    if (!title.trim() || !description.trim() || !category.trim()) {
      formError = "Title, description, and category are required.";
      return;
    }

    formLoading = true;
    formError = "";

    let imageUrl: string | null = null;

    if (imageFile) {
      const { data: latestSession } = await supabase.auth.getSession();
      const accessTokenPresent = Boolean(latestSession.session?.access_token);
      console.log("[upload] session token present:", accessTokenPresent);

      const fileExt = imageFile.name.split(".").pop() || "jpg";
      const filePath = `${session.user.id}/${crypto.randomUUID()}.${fileExt}`;
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from(imageBucket)
        .upload(filePath, imageFile, { contentType: imageFile.type, upsert: false });

      if (uploadError) {
        console.error("[upload] failed:", {
          message: uploadError.message,
          name: uploadError.name,
          status: uploadError.status,
          details: uploadError.details,
          filePath,
          bucket: imageBucket,
        });
        formError = uploadError.message;
        formLoading = false;
        return;
      }
      console.log("[upload] success:", uploadData);

      const { data: imageData } = supabase.storage.from(imageBucket).getPublicUrl(filePath);
      imageUrl = imageData.publicUrl;
      console.log("[upload] public url:", imageUrl);
    }

    const payload = {
      title: title.trim(),
      description: description.trim(),
      category: category.trim(),
      status: defaultStatus,
      image_url: imageUrl,
      location_found: locationFound.trim() ? locationFound.trim() : null,
      created_by: session.user.id,
    };

    const { data, error } = await supabase.from("items").insert([payload]).select().single();

    if (error) {
      formError = error.message;
    } else if (data) {
      items = [data as ItemRow, ...items];
      title = "";
      description = "";
      category = "";
      imageFile = null;
      if (imageInput) {
        imageInput.value = "";
      }
      locationFound = "";
    }

    formLoading = false;
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

<div class="min-h-screen bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 py-8 px-4">
  <div class="max-w-6xl mx-auto space-y-8">
    <header class="bg-white rounded-2xl shadow-2xl p-6 md:p-10 text-center">
      <h1 class="text-3xl md:text-4xl font-bold text-gray-800">Lost and Found</h1>
      <p class="mt-2 text-gray-600">Submit, track, and update community lost-and-found items.</p>
    </header>

    <section class="bg-white rounded-2xl shadow-2xl p-6 md:p-10">
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h2 class="text-2xl font-bold text-gray-800">User Session</h2>
          <p class="text-sm text-gray-500">Sign in to submit items. Librarians can manage item statuses.</p>
        </div>

        {#if session}
          <div class="flex flex-col md:items-end gap-2">
            <span class="text-sm text-gray-600">Signed in as <strong>{session.user.email}</strong></span>
            <span class="text-xs uppercase tracking-wide text-gray-500">Role: {userRole ?? "unknown"}</span>
            <button
              class="px-4 py-2 bg-gray-900 text-white rounded-lg hover:bg-gray-800 transition-colors"
              on:click={handleLogout}
              disabled={authLoading}
            >
              Log out
            </button>
          </div>
        {:else}
          <div class="flex flex-col md:flex-row gap-3">
            <input
              type="email"
              placeholder="Email"
              class="w-full md:w-56 px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
              bind:value={email}
            />
            <input
              type="password"
              placeholder="Password"
              class="w-full md:w-56 px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
              bind:value={password}
            />
            <button
              class="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors"
              on:click={handleAuthSubmit}
              disabled={authLoading}
            >
              {isSigningUp ? "Sign up" : "Sign in"}
            </button>
          </div>
        {/if}
      </div>

      {#if !session}
        <div class="mt-4">
          <button
            class="text-sm text-indigo-600 hover:text-indigo-800"
            on:click={() => {
              isSigningUp = !isSigningUp;
              authError = "";
            }}
          >
            {isSigningUp ? "Already have an account? Sign in" : "New here? Create an account"}
          </button>
        </div>
      {/if}

      {#if authError}
        <div class="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg">
          {authError}
        </div>
      {/if}
    </section>

    <section class="bg-white rounded-2xl shadow-2xl p-6 md:p-10">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <h2 class="text-2xl font-bold text-gray-800">Submit an Item</h2>
        {#if !session}
          <span class="text-sm text-gray-500">Sign in required</span>
        {/if}
      </div>

      <div class="mt-6 grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="space-y-2">
          <label class="text-sm font-medium text-gray-700" for="title-input">Title *</label>
          <input
            id="title-input"
            type="text"
            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
            placeholder="Blue backpack"
            bind:value={title}
          />
        </div>
        <div class="space-y-2">
          <label class="text-sm font-medium text-gray-700" for="category-input">Category *</label>
          <input
            id="category-input"
            type="text"
            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
            placeholder="Accessories"
            bind:value={category}
          />
        </div>
        <div class="md:col-span-2 space-y-2">
          <label class="text-sm font-medium text-gray-700" for="description-input">Description *</label>
          <textarea
            id="description-input"
            rows="3"
            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
            placeholder="Red tag with initials on the zipper"
            bind:value={description}
          ></textarea>
        </div>
        <div class="space-y-2">
          <label class="text-sm font-medium text-gray-700" for="location-input">Location Found</label>
          <input
            id="location-input"
            type="text"
            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
            placeholder="Library entrance"
            bind:value={locationFound}
          />
        </div>
        <div class="md:col-span-2 space-y-2">
          <label class="text-sm font-medium text-gray-700" for="image-input">Image</label>
          <input
            bind:this={imageInput}
            id="image-input"
            type="file"
            accept="image/*"
            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
            on:change={(event) => {
              const file = (event.target as HTMLInputElement).files?.[0];
              imageFile = file ?? null;
            }}
          />
        </div>
      </div>

      {#if formError}
        <div class="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg">
          {formError}
        </div>
      {/if}

      <div class="mt-6 flex flex-wrap gap-3">
        <button
          class="px-6 py-3 bg-gradient-to-r from-indigo-500 to-purple-600 text-white rounded-lg font-medium hover:from-indigo-600 hover:to-purple-700 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
          on:click={handleSubmitItem}
          disabled={formLoading || !session}
        >
          {formLoading ? "Submitting..." : "Submit Item"}
        </button>
        <button
          class="px-6 py-3 bg-gray-100 text-gray-700 border border-gray-300 rounded-lg font-medium hover:bg-gray-200 transition-colors"
          on:click={() => {
            title = "";
            description = "";
            category = "";
            imageFile = null;
            if (imageInput) {
              imageInput.value = "";
            }
            locationFound = "";
            formError = "";
          }}
        >
          Clear
        </button>
      </div>
    </section>

    <section class="bg-white rounded-2xl shadow-2xl p-6 md:p-10">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <h2 class="text-2xl font-bold text-gray-800">Items</h2>
        <button class="text-sm text-indigo-600 hover:text-indigo-800" on:click={loadItems} disabled={itemsLoading}>
          Refresh list
        </button>
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
            <article class="bg-gray-50 rounded-xl overflow-hidden shadow-md flex flex-col">
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
  </div>
</div>
