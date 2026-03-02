<script lang="ts">
  import { onMount } from "svelte";
  import { goto } from "$app/navigation";
  import { ArrowLeft } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";

  let session: Session | null = null;

  let title = "";
  let description = "";
  let category = "";
  let locationFound = "";
  let imageFile: File | null = null;
  let imageInput: HTMLInputElement | null = null;

  let formError = "";
  let formLoading = false;

  const defaultStatus = "lost";
  const imageBucket = "item-images";

  async function loadSession() {
    const { data } = await supabase.auth.getSession();
    session = data.session;
    if (!data.session) {
      await goto("/");
    }
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
      const fileExt = imageFile.name.split(".").pop() || "jpg";
      const filePath = `${session.user.id}/${crypto.randomUUID()}.${fileExt}`;
      const { error: uploadError } = await supabase.storage
        .from(imageBucket)
        .upload(filePath, imageFile, { contentType: imageFile.type, upsert: false });

      if (uploadError) {
        formError = uploadError.message;
        formLoading = false;
        return;
      }

      const { data: imageData } = supabase.storage.from(imageBucket).getPublicUrl(filePath);
      imageUrl = imageData.publicUrl;
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

    const { error } = await supabase.from("items").insert([payload]);

    if (error) {
      formError = error.message;
    } else {
      toast.success("Item submitted successfully.");
      await goto("/");
    }

    formLoading = false;
  }

  function clearForm() {
    title = "";
    description = "";
    category = "";
    locationFound = "";
    imageFile = null;
    if (imageInput) {
      imageInput.value = "";
    }
    formError = "";
  }

  onMount(() => {
    loadSession();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      session = nextSession;
      if (!nextSession) {
        goto("/");
      }
    });

    return () => {
      data.subscription.unsubscribe();
    };
  });
</script>

<svelte:head>
  <title>Submit Item | Lost and Found</title>
  <meta name="description" content="Submit a lost-and-found item" />
</svelte:head>

<div class="min-h-screen bg-gray-100">
  <header class="bg-white border-b border-gray-200">
    <div class="max-w-6xl mx-auto px-4 py-4 md:py-5">
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div class="text-left">
          <a
            href="/"
            aria-label="Back to items"
            class="inline-flex items-center gap-1 px-2 py-1 rounded-md border border-gray-300 text-gray-700 text-sm hover:bg-gray-100"
          >
            <ArrowLeft size={18} />
            <span>Back to items</span>
          </a>
          <h1 class="text-left text-2xl md:text-3xl font-bold text-gray-800 leading-tight mt-1">Submit an Item</h1>
        </div>
      </div>
    </div>
  </header>

  <main class="max-w-4xl mx-auto px-4 py-6">
    <section class="bg-white border border-gray-200 p-6 md:p-8">
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
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
          class="px-4 py-2 bg-indigo-600 text-white rounded-lg font-medium disabled:cursor-not-allowed disabled:opacity-60"
          on:click={handleSubmitItem}
          disabled={formLoading || !session}
        >
          {formLoading ? "Submitting..." : "Submit Item"}
        </button>
        <button
          class="px-4 py-2 bg-gray-100 text-gray-700 border border-gray-300 rounded-lg font-medium hover:bg-gray-200 transition-colors"
          on:click={clearForm}
        >
          Clear
        </button>
      </div>
    </section>
  </main>
</div>
