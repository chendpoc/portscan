<script lang="ts">
  type Props = { count: number; query: string }
  let { count, query }: Props = $props()
</script>

{#if query.trim()}
  <div class="search-summary">
    <strong>{count} matching process{count === 1 ? '' : 'es'}</strong>
    <span>Project / CWD distinguishes same-name runtimes</span>
  </div>
{/if}
