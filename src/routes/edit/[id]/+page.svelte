<script lang="ts">
    import { onMount } from "svelte";
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { ArrowLeft } from "lucide-svelte";
    import type { Session } from "@supabase/supabase-js";
    import { supabase } from "$lib/supabaseClient";
    import { toast } from "svelte-sonner";

    let session: Session | null = null;
    const itemId = $page.params.id;

    let title = "";
    let description = "";
    let category = "";
    let locationFound = "";
    let imageUrl: string | null = null;

    let imageFile: File | null = null;
    let imageInput: HTMLInputElement | null = null;

    let formError = "";
    let formLoading = false;
    let pageLoading = true;

    const imageBucket = "item-images";

    async function loadSessionAndItem() {
        const { data: authData } = await supabase.auth.getSession();
        session = authData.session;
        if (!authData.session) {
            await goto("/");
            return;
        }

        const { data: itemData, error } = await supabase
            .from("items")
            .select("*")
            .eq("id", itemId)
            .single();

        if (error || !itemData) {
            toast.error("Item not found");
            await goto("/");
            return;
        }

        if (!session || itemData.created_by !== session.user.id) {
            toast.error("You don't have permission to edit this item");
            await goto("/");
            return;
        }

        title = itemData.title;
        description = itemData.description;
        category = itemData.category;
        locationFound = itemData.location_found || "";
        imageUrl = itemData.image_url;

        pageLoading = false;
    }

    async function handleUpdateItem() {
        if (!session?.user) {
            formError = "Please sign in to update an item.";
            return;
        }

        if (!title.trim() || !description.trim() || !category.trim()) {
            formError = "Title, description, and category are required.";
            return;
        }

        formLoading = true;
        formError = "";

        let newImageUrl: string | null = imageUrl;

        if (imageFile) {
            const fileExt = imageFile.name.split(".").pop() || "jpg";
            const filePath = `${session.user.id}/${crypto.randomUUID()}.${fileExt}`;
            const { error: uploadError } = await supabase.storage
                .from(imageBucket)
                .upload(filePath, imageFile, {
                    contentType: imageFile.type,
                    upsert: false,
                });

            if (uploadError) {
                formError = uploadError.message;
                formLoading = false;
                return;
            }

            const { data: imageData } = supabase.storage
                .from(imageBucket)
                .getPublicUrl(filePath);
            newImageUrl = imageData.publicUrl;
        }

        const payload = {
            title: title.trim(),
            description: description.trim(),
            category: category.trim(),
            location_found: locationFound.trim() ? locationFound.trim() : null,
            image_url: newImageUrl,
        };

        const { error } = await supabase
            .from("items")
            .update(payload)
            .eq("id", itemId)
            .eq("created_by", session.user.id)
            .select()
            .single();

        if (error) {
            formError = "Failed to update item: " + error.message;
        } else {
            toast.success("Item updated successfully.");
            await goto("/");
        }

        formLoading = false;
    }

    onMount(() => {
        loadSessionAndItem();

        const { data } = supabase.auth.onAuthStateChange(
            (_event, nextSession) => {
                session = nextSession;
                if (!nextSession) {
                    goto("/");
                }
            },
        );

        return () => {
            data.subscription.unsubscribe();
        };
    });
</script>

<svelte:head>
    <title>Edit Item | Lost and Found</title>
</svelte:head>

<div class="min-h-screen bg-gray-100">
    <header class="bg-white border-b border-gray-200">
        <div class="max-w-6xl mx-auto px-4 py-4 md:py-5">
            <div
                class="flex flex-col md:flex-row md:items-center md:justify-between gap-4"
            >
                <div class="text-left">
                    <a
                        href="/"
                        class="inline-flex items-center gap-1 px-2 py-1 rounded-md border border-gray-300 text-gray-700 text-sm hover:bg-gray-100"
                    >
                        <ArrowLeft size={18} />
                        <span>Back to items</span>
                    </a>
                    <h1
                        class="text-left text-2xl md:text-3xl font-bold text-gray-800 leading-tight mt-1"
                    >
                        Edit Item
                    </h1>
                </div>
            </div>
        </div>
    </header>

    <main class="max-w-4xl mx-auto px-4 py-6">
        {#if pageLoading}
            <p class="text-gray-500">Loading item...</p>
        {:else}
            <section class="bg-white border border-gray-200 p-6 md:p-8">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="space-y-2">
                        <label
                            class="text-sm font-medium text-gray-700"
                            for="title-input">Title *</label
                        >
                        <input
                            id="title-input"
                            type="text"
                            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
                            bind:value={title}
                        />
                    </div>
                    <div class="space-y-2">
                        <label
                            class="text-sm font-medium text-gray-700"
                            for="category-input">Category *</label
                        >
                        <input
                            id="category-input"
                            type="text"
                            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
                            bind:value={category}
                        />
                    </div>
                    <div class="md:col-span-2 space-y-2">
                        <label
                            class="text-sm font-medium text-gray-700"
                            for="description-input">Description *</label
                        >
                        <textarea
                            id="description-input"
                            rows="3"
                            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
                            bind:value={description}
                        ></textarea>
                    </div>
                    <div class="space-y-2">
                        <label
                            class="text-sm font-medium text-gray-700"
                            for="location-input">Location Found</label
                        >
                        <input
                            id="location-input"
                            type="text"
                            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
                            bind:value={locationFound}
                        />
                    </div>
                    <div class="md:col-span-2 space-y-2">
                        <label
                            class="text-sm font-medium text-gray-700"
                            for="image-input">Update Image (Optional)</label
                        >
                        {#if imageUrl && !imageFile}
                            <div class="mb-2">
                                <img
                                    src={imageUrl}
                                    alt="Current item"
                                    class="h-32 rounded-lg object-cover border border-gray-200"
                                />
                            </div>
                        {/if}
                        <input
                            bind:this={imageInput}
                            id="image-input"
                            type="file"
                            accept="image/*"
                            class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500"
                            on:change={(event) => {
                                const file = (event.target as HTMLInputElement)
                                    .files?.[0];
                                imageFile = file ?? null;
                            }}
                        />
                    </div>
                </div>

                {#if formError}
                    <div
                        class="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg"
                    >
                        {formError}
                    </div>
                {/if}

                <div class="mt-6 flex flex-wrap gap-3">
                    <button
                        class="px-4 py-2 bg-indigo-600 text-white rounded-lg font-medium disabled:cursor-not-allowed disabled:opacity-60 hover:bg-indigo-700 transition-colors"
                        on:click={handleUpdateItem}
                        disabled={formLoading || !session}
                    >
                        {formLoading ? "Saving..." : "Save Changes"}
                    </button>
                </div>
            </section>
        {/if}
    </main>
</div>
