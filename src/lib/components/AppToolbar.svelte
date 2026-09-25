<script lang="ts">
  import type { PrimaryView } from '$lib/types'

  type Props = {
    preview: boolean
    view: PrimaryView
    query: string
    refreshing: boolean
    onQuery: (value: string) => void
    onClear: () => void
    onView: (view: PrimaryView) => void
    onRefresh: () => void
  }

  let { preview, view, query, refreshing, onQuery, onClear, onView, onRefresh }: Props = $props()
</script>

<header class="window-toolbar" data-tauri-drag-region="deep">
  <div class="toolbar-title">
    {#if preview}
      <img class="preview-lights" src="/figma/traffic-lights.svg" alt="" aria-hidden="true" />
    {/if}
    <span class="app-name">PortMaster</span>
  </div>
  <div class="toolbar-controls">
    <div class="segmented-control" role="group" aria-label="Primary view">
      <button class:active={view === 'processes'} type="button" aria-pressed={view === 'processes'} onclick={() => onView('processes')}>Processes</button>
      <button class:active={view === 'ports'} type="button" aria-pressed={view === 'ports'} onclick={() => onView('ports')}>Ports</button>
    </div>
    <label class="search-box">
      <img src="/figma/search.svg" alt="" aria-hidden="true" />
      <input
        type="search"
        placeholder={view === 'ports' ? 'Port, process or project…' : 'Process, PID, port or project…'}
        aria-label="Search"
        value={query}
        oninput={(event) => onQuery((event.currentTarget as HTMLInputElement).value)}
      />
      {#if query}
        <button class="clear-search" type="button" aria-label="Clear search" onclick={onClear}>×</button>
      {/if}
    </label>
    <button class="icon-button" type="button" aria-label="Refresh now" disabled={refreshing} onclick={onRefresh}>
      <img src="/figma/refresh-cw.svg" alt="" aria-hidden="true" />
    </button>
  </div>
</header>
