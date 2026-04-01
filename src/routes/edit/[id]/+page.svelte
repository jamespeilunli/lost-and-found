<script lang="ts">
  import { onMount } from "svelte";
  import { goto } from "$app/navigation";
  import { page } from "$app/stores";
  import { ArrowLeft } from "lucide-svelte";
  import type { Session } from "@supabase/supabase-js";
  import { supabase } from "$lib/supabaseClient";
  import { toast } from "svelte-sonner";
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Button } from "$lib/components/ui/button";
  import {
    Card,
    CardContent,
    CardDescription,
    CardFooter,
    CardHeader,
    CardTitle,
  } from "$lib/components/ui/card";
  import { Input } from "$lib/components/ui/input";
  import { Label } from "$lib/components/ui/label";
  import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
  } from "$lib/components/ui/select";
  import { Textarea } from "$lib/components/ui/textarea";

  let session: Session | null = null;
  const itemId = $page.params.id;

  let title = "";
  let description = "";
  const CATEGORY_OPTIONS = [
    "Accessories",
    "Bags / Backpacks",
    "Clothing",
    "Electronics",
    "ID / Cards",
    "Keys",
    "Wallet",
    "Other",
  ];
  let selectedCategory = "";
  let customCategory = "";
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
    if (CATEGORY_OPTIONS.includes(itemData.category)) {
      selectedCategory = itemData.category;
      customCategory = "";
    } else {
      selectedCategory = "Other";
      customCategory = itemData.category;
    }
    locationFound = itemData.location_found || "";
    imageUrl = itemData.image_url;

    pageLoading = false;
  }

  async function handleUpdateItem() {
    if (!session?.user) {
      formError = "Please sign in to update an item.";
      return;
    }

    const finalCategory = (
      selectedCategory === "Other" ? customCategory : selectedCategory
    ).trim();

    if (!title.trim() || !description.trim() || !finalCategory) {
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
      category: finalCategory,
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

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-6xl px-4 py-4 md:py-5">
      <div class="flex flex-col gap-4">
        <div class="text-left">
          <Button href="/" variant="outline" size="sm" class="gap-1">
            <ArrowLeft size={18} />
            <span>Back to items</span>
          </Button>
          <h1 class="mt-2 text-left text-2xl font-bold leading-tight md:text-3xl">
            Edit Item
          </h1>
          <p class="mt-1 text-sm text-muted-foreground">
            Update the current report without changing its original status.
          </p>
        </div>
      </div>
    </div>
  </header>

  <main class="mx-auto max-w-4xl px-4 py-6">
    {#if pageLoading}
      <p class="text-muted-foreground">Loading item...</p>
    {:else}
      <Card class="border-border/80 bg-card shadow-none">
        <CardHeader>
          <CardTitle>Item details</CardTitle>
          <CardDescription>
            Adjust the report details and optionally replace the image.
          </CardDescription>
        </CardHeader>
        <CardContent class="space-y-6">
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div class="space-y-2">
              <Label for="title-input">Title *</Label>
              <Input id="title-input" type="text" bind:value={title} />
            </div>

            <div class="space-y-2">
              <Label for="category-select-trigger">Category *</Label>
              <Select type="single" bind:value={selectedCategory}>
                <SelectTrigger
                  id="category-select-trigger"
                  class="w-full justify-between bg-background"
                >
                  {selectedCategory || "Select a category"}
                </SelectTrigger>
                <SelectContent>
                  {#each CATEGORY_OPTIONS as option}
                    <SelectItem value={option} label={option} />
                  {/each}
                </SelectContent>
              </Select>
              {#if selectedCategory === "Other"}
                <Input
                  id="category-input"
                  type="text"
                  placeholder="Please specify"
                  bind:value={customCategory}
                />
              {/if}
            </div>

            <div class="space-y-2 md:col-span-2">
              <Label for="description-input">Description *</Label>
              <Textarea id="description-input" rows={4} bind:value={description} />
            </div>

            <div class="space-y-2">
              <Label for="location-input">Location Found</Label>
              <Input id="location-input" type="text" bind:value={locationFound} />
            </div>

            <div class="space-y-2 md:col-span-2">
              <Label for="image-input">Update Image</Label>
              {#if imageUrl && !imageFile}
                <img
                  src={imageUrl}
                  alt="Current item"
                  class="h-32 border object-cover"
                />
              {/if}
              <Input
                bind:ref={imageInput}
                id="image-input"
                type="file"
                accept="image/*"
                class="bg-background"
                onchange={(event: Event) => {
                  const file = (event.currentTarget as HTMLInputElement).files?.[0];
                  imageFile = file ?? null;
                }}
              />
            </div>
          </div>

          {#if formError}
            <Alert variant="destructive">
              <AlertTitle>Could not update item</AlertTitle>
              <AlertDescription>{formError}</AlertDescription>
            </Alert>
          {/if}
        </CardContent>

        <CardFooter class="flex flex-wrap gap-3">
          <Button onclick={handleUpdateItem} disabled={formLoading || !session}>
            {formLoading ? "Saving..." : "Save Changes"}
          </Button>
        </CardFooter>
      </Card>
    {/if}
  </main>
</div>
