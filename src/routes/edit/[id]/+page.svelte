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
  let status = "found";
  let manualDueDate = "";
  let imageUrl: string | null = null;

  $: headingText = status === "claimed" ? "Edit claimed item" : "Edit item at library";
  $: subtitleText = "Update the inventory details and pickup deadline.";

  let imageFile: File | null = null;
  let imageInput: HTMLInputElement | null = null;

  let formError = "";
  let formLoading = false;
  let pageLoading = true;

  const imageBucket = "item-images";
  const itemSelectColumns =
    "id,title,description,category,status,image_url,location_found,created_at,manual_due_date";

  async function loadSessionAndItem() {
    const { data: authData } = await supabase.auth.getSession();
    session = authData.session;
    if (!authData.session) {
      await goto("/");
      return;
    }

    const { data: itemData, error } = await supabase
      .from("items")
      .select(itemSelectColumns)
      .eq("id", itemId)
      .single();

    if (error || !itemData) {
      toast.error(error?.message ?? "Item not found");
      await goto("/");
      return;
    }

    if (itemData.status === "lost") {
      toast.error("Lost reports are no longer editable.");
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
    status = itemData.status || "found";
    manualDueDate = itemData.manual_due_date || "";
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
      status,
      manual_due_date: manualDueDate || null,
    };

    const { error } = await supabase
      .from("items")
      .update(payload)
      .eq("id", itemId)
      .select(itemSelectColumns)
      .single();

    if (error) {
      formError = error.message.toLowerCase().includes("row-level security")
        ? "This signed-in account is not approved to update inventory."
        : "Failed to update item: " + error.message;
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
  <title>{headingText} | Lost and Found</title>
</svelte:head>

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-6xl px-4 py-4 md:py-5">
      <div class="flex flex-col gap-4">
        <div class="text-left">
          <Button href="/" variant="outline" size="sm" class="gap-1 text-sm">
            <ArrowLeft size={18} />
            <span>Back to items</span>
          </Button>
          <h1 class="mt-2 text-left text-2xl font-bold leading-tight md:text-3xl">
            {headingText}
          </h1>
          <p class="mt-1 text-sm text-muted-foreground">
            {subtitleText}
          </p>
        </div>
      </div>
    </div>
  </header>

  <main class="mx-auto max-w-4xl px-4 py-6">
    {#if pageLoading}
      <p class="text-muted-foreground">Loading item...</p>
    {:else}
      <Card class="border-border/80 bg-card text-sm shadow-none">
        <CardHeader>
          <CardTitle>Item details</CardTitle>
          <CardDescription class="text-sm">
            Adjust the report details and optionally replace the image.
          </CardDescription>
        </CardHeader>
        <CardContent class="space-y-6">
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div class="space-y-2">
              <Label class="text-sm" for="title-input">Title *</Label>
              <Input class="text-sm" id="title-input" type="text" bind:value={title} />
            </div>

            <div class="space-y-2">
              <Label class="text-sm" for="category-select-trigger">Category *</Label>
              <Select type="single" bind:value={selectedCategory}>
                <SelectTrigger
                  id="category-select-trigger"
                  class="w-full justify-between bg-background text-sm"
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
                  class="text-sm"
                  placeholder="Please specify"
                  bind:value={customCategory}
                />
              {/if}
            </div>

            <div class="space-y-2 md:col-span-2">
              <Label class="text-sm" for="description-input">Description *</Label>
              <Textarea class="text-sm" id="description-input" rows={4} bind:value={description} />
            </div>

            <div class="space-y-2">
              <Label class="text-sm" for="location-input">Location found</Label>
              <Input class="text-sm" id="location-input" type="text" bind:value={locationFound} />
            </div>

            <div class="space-y-2">
              <Label class="text-sm" for="status-select-trigger">Status</Label>
              <Select type="single" bind:value={status}>
                <SelectTrigger
                  id="status-select-trigger"
                  class="w-full justify-between bg-background text-sm"
                >
                  {status === "claimed" ? "Claimed" : "At library"}
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="found" label="At library" />
                  <SelectItem value="claimed" label="Claimed" />
                </SelectContent>
              </Select>
            </div>

            <div class="space-y-2">
              <Label class="text-sm" for="manual-due-date-input">Pickup deadline override</Label>
              <Input
                id="manual-due-date-input"
                type="date"
                class="text-sm"
                bind:value={manualDueDate}
              />
              <p class="text-xs text-muted-foreground">Leave blank to use the automatic month-end deadline.</p>
            </div>

            <div class="space-y-2 md:col-span-2">
              <Label class="text-sm" for="image-input">Update Image</Label>
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
                class="bg-background text-sm"
                onchange={(event: Event) => {
                  const file = (event.currentTarget as HTMLInputElement).files?.[0];
                  imageFile = file ?? null;
                }}
              />
            </div>
          </div>

          {#if formError}
            <Alert variant="destructive" class="text-sm">
              <AlertTitle>Could not update item</AlertTitle>
              <AlertDescription>{formError}</AlertDescription>
            </Alert>
          {/if}
        </CardContent>

        <CardFooter class="flex flex-wrap gap-3">
          <Button class="text-sm" onclick={handleUpdateItem} disabled={formLoading || !session}>
            {formLoading ? "Saving..." : "Save Changes"}
          </Button>
        </CardFooter>
      </Card>
    {/if}
  </main>
</div>
