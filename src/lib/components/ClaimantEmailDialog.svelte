<script lang="ts">
  import { Alert, AlertDescription, AlertTitle } from "$lib/components/ui/alert";
  import { Button } from "$lib/components/ui/button";
  import * as Dialog from "$lib/components/ui/dialog";
  import { Input } from "$lib/components/ui/input";
  import { Label } from "$lib/components/ui/label";

  export let open = false;
  export let itemTitle = "";
  export let saving = false;
  export let error = "";
  export let onSubmit: (email: string) => void | Promise<void>;

  let email = "";
  let validationError = "";
  let wasOpen = false;

  $: if (open && !wasOpen) {
    email = "";
    validationError = "";
  }
  $: wasOpen = open;

  function handleSubmit(event: SubmitEvent) {
    event.preventDefault();

    const normalizedEmail = email.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalizedEmail)) {
      validationError = "Enter a valid email address.";
      return;
    }

    validationError = "";
    void onSubmit(normalizedEmail);
  }
</script>

<Dialog.Root bind:open>
  <Dialog.Content
    class="sm:max-w-md"
    showCloseButton={!saving}
    onInteractOutside={(event) => saving && event.preventDefault()}
    onEscapeKeydown={(event) => saving && event.preventDefault()}
  >
    <form class="flex flex-col gap-5" onsubmit={handleSubmit}>
      <Dialog.Header>
        <Dialog.Title>Mark item as claimed</Dialog.Title>
        <Dialog.Description>
          Enter the email of the person claiming “{itemTitle}”. The item will not be updated until you submit.
        </Dialog.Description>
      </Dialog.Header>

      <div class="flex flex-col gap-2">
        <Label for="claimant-email-input">Claimant email *</Label>
        <Input
          id="claimant-email-input"
          name="claimantEmail"
          type="email"
          autocomplete="email"
          placeholder="name@example.com"
          bind:value={email}
          aria-invalid={Boolean(validationError)}
          aria-describedby={validationError ? "claimant-email-error" : undefined}
          disabled={saving}
          required
        />
        {#if validationError}
          <p id="claimant-email-error" class="text-xs text-destructive">{validationError}</p>
        {/if}
      </div>

      {#if error}
        <Alert variant="destructive">
          <AlertTitle>Could not save claimant email</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      {/if}

      <Dialog.Footer>
        <Button type="button" variant="outline" onclick={() => (open = false)} disabled={saving}>
          Cancel
        </Button>
        <Button type="submit" disabled={saving}>
          {saving ? "Saving..." : "Mark as claimed"}
        </Button>
      </Dialog.Footer>
    </form>
  </Dialog.Content>
</Dialog.Root>
