<script lang="ts">
  import { onMount } from "svelte";
  import { goto } from "$app/navigation";
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
      formError = "Please sign in to add an item.";
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

    let imageUrl: string | null = null;

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
      imageUrl = imageData.publicUrl;
    }

    const payload = {
      title: title.trim(),
      description: description.trim(),
      category: finalCategory,
      status: defaultStatus,
      image_url: imageUrl,
      location_found: locationFound.trim() ? locationFound.trim() : null,
      created_by: session.user.id,
    };

    const { error } = await supabase
      .from("items")
      .insert([payload])
      .select()
      .single();

    if (error) {
      formError = "Failed to add item: " + error.message;
    } else {
      toast.success("Item added successfully.");
      await goto("/");
    }

    formLoading = false;
  }

  function clearForm() {
    title = "";
    description = "";
    selectedCategory = "";
    customCategory = "";
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
  <title>Report a lost item | Lost and Found</title>
  <meta name="description" content="Report an item you've lost" />
</svelte:head>

<div class="min-h-screen bg-background text-foreground transition-colors duration-200">
  <header class="border-b bg-card/95 backdrop-blur-sm transition-colors duration-200">
    <div class="mx-auto max-w-4xl px-4 py-4 md:py-5">
      <div class="flex flex-col gap-4">
        <div class="text-left">
          <Button href="/" variant="outline" size="sm" class="gap-1 text-sm">
            <ArrowLeft size={18} />
            <span>Back</span>
          </Button>
          <h1 class="mt-2 text-left text-2xl font-bold leading-tight md:text-3xl">
            Report a lost item
          </h1>
          <p class="mt-1 text-sm text-muted-foreground">
            Describe what you lost so a librarian can match it when someone turns it in.
          </p>
        </div>
      </div>
    </div>
  </header>

  <main class="mx-auto max-w-4xl px-4 py-6">
    <Card class="border-border/80 bg-card text-sm shadow-none">
      <CardHeader>
        <CardTitle>Item details</CardTitle>
        <CardDescription class="text-sm">
          Required fields are marked with an asterisk.
        </CardDescription>
      </CardHeader>
      <CardContent class="space-y-6">
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div class="space-y-2">
            <Label class="text-sm" for="title-input">Title *</Label>
            <Input
              id="title-input"
              type="text"
              class="text-sm"
              placeholder="Blue backpack"
              bind:value={title}
            />
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
            <Textarea
              id="description-input"
              class="text-sm"
              rows={4}
              placeholder="Red tag with initials on the zipper"
              bind:value={description}
            />
          </div>

          <div class="space-y-2">
            <Label class="text-sm" for="location-input">Last seen location</Label>
            <Input
              id="location-input"
              type="text"
              class="text-sm"
              placeholder="e.g. Library, 2nd floor study room"
              bind:value={locationFound}
            />
          </div>

          <div class="space-y-2 md:col-span-2">
            <Label class="text-sm" for="image-input">Image</Label>
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
            <AlertTitle>Could not add item</AlertTitle>
            <AlertDescription>{formError}</AlertDescription>
          </Alert>
        {/if}
      </CardContent>
      <CardFooter class="flex flex-wrap gap-3">
        <Button class="text-sm" onclick={handleSubmitItem} disabled={formLoading || !session}>
          {formLoading ? "Submitting..." : "Report lost item"}
        </Button>
        <Button variant="outline" class="text-sm" onclick={clearForm}>
          Clear
        </Button>
      </CardFooter>
    </Card>
  </main>
</div>
