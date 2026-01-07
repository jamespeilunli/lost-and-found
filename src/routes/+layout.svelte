<script lang="ts">
  import './layout.css';

  let { children } = $props();
</script>

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
