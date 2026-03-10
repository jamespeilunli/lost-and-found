<script lang="ts">
  import { onMount } from "svelte";
  import "./layout.css";
  import { Toaster } from "svelte-sonner";

  let { children } = $props();
  let currentTheme = $state<"light" | "dark" | "system">("system");

  onMount(() => {
    if (document.documentElement.classList.contains("dark")) {
      currentTheme = "dark";
    } else {
      currentTheme = "light";
    }

    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.attributeName === "class") {
          currentTheme = document.documentElement.classList.contains("dark")
            ? "dark"
            : "light";
        }
      });
    });

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"],
    });

    return () => observer.disconnect();
  });
</script>

<Toaster richColors theme={currentTheme} />

<div class="app">
  <main>{@render children()}</main>
</div>

<style>
  .app {
    display: flex;
    flex-direction: column;
    min-height: 100vh;
  }

  main {
    flex: 1;
    width: 100%;
    box-sizing: border-box;
  }
</style>
