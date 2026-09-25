<script lang="ts">
  import { formatTime } from '$lib/format'
  import type { PrimaryView, RefreshSettings, RenderStatus } from '$lib/types'

  type Props = {
    view: PrimaryView
    status: RenderStatus
    settings: RefreshSettings
    capturedAt: string
    summary: string
    preview?: boolean
    open: boolean
    onToggle: () => void
    onInterval: (ms: number) => void
    onUdp: (value: boolean) => void
    onIpv6: (value: boolean) => void
    onPaused: (value: boolean) => void
    onProcessFilter?: (value: 'all' | 'running' | 'with_listeners') => void
    processFilter?: 'all' | 'running' | 'with_listeners'
    protocol?: 'all' | 'tcp' | 'udp'
    connectionState?: string
    onProtocol?: (value: 'all' | 'tcp' | 'udp') => void
    onConnectionState?: (value: string) => void
    portsFilter?: 'listeners' | 'all'
    onPortsFilter?: (value: 'listeners' | 'all') => void
  }

  let {
    view,
    status,
    settings,
    capturedAt,
    summary,
    preview = false,
    open,
    onToggle,
    onInterval,
    onUdp,
    onIpv6,
    onPaused,
    onProcessFilter,
    processFilter = 'all',
    protocol = 'all',
    onProtocol,
    onConnectionState,
    connectionState = 'all',
    portsFilter = 'listeners',
    onPortsFilter,
  }: Props = $props()
</script>

<footer class="status-bar">
  <button class="status-summary" type="button" aria-expanded={open} onclick={onToggle}>{summary}</button>
  <span class="status-meta">
    {#if preview}<span class="preview-badge">Preview fixture</span>{/if}
    {settings.paused ? 'Paused' : status === 'stale' ? 'Stale' : status === 'error' ? 'Error' : 'Live'}
    · {settings.intervalMs / 1000}s · {formatTime(capturedAt)}
    <i class:live={status === 'live' && !settings.paused} aria-hidden="true"></i>
  </span>
  {#if open}
    <div class="status-popover">
      {#if view === 'processes' && onProcessFilter}
        <div class="popover-title">Process filter</div>
        <div class="segmented-control mini" role="group">
          <button class:active={processFilter === 'all'} type="button" onclick={() => onProcessFilter('all')}>All</button>
          <button class:active={processFilter === 'running'} type="button" onclick={() => onProcessFilter('running')}>Running</button>
          <button class:active={processFilter === 'with_listeners'} type="button" onclick={() => onProcessFilter('with_listeners')}>With listeners</button>
        </div>
      {/if}
      {#if view === 'ports'}
        <div class="popover-title">Ports view</div>
        <div class="segmented-control mini" role="group">
          <button class:active={portsFilter === 'listeners'} type="button" onclick={() => onPortsFilter?.('listeners')}>Listeners</button>
          <button class:active={portsFilter === 'all'} type="button" onclick={() => onPortsFilter?.('all')}>All sockets</button>
        </div>
        {#if onProtocol}
          <div class="popover-title">Protocol</div>
          <div class="segmented-control mini" role="group">
            <button class:active={protocol === 'all'} type="button" onclick={() => onProtocol('all')}>All</button>
            <button class:active={protocol === 'tcp'} type="button" onclick={() => onProtocol('tcp')}>TCP</button>
            <button class:active={protocol === 'udp'} type="button" onclick={() => onProtocol('udp')}>UDP</button>
          </div>
        {/if}
        {#if onConnectionState}
          <div class="popover-title">Connection state</div>
          <div class="segmented-control mini connection-states" role="group" aria-label="Connection state filter">
            <button class:active={connectionState === 'all'} type="button" onclick={() => onConnectionState('all')}>All</button>
            <button class:active={connectionState === 'listen'} type="button" onclick={() => onConnectionState('listen')}>Listen</button>
            <button class:active={connectionState === 'established'} type="button" onclick={() => onConnectionState('established')}>Established</button>
            <button class:active={connectionState === 'none'} type="button" onclick={() => onConnectionState('none')}>Bound</button>
          </div>
        {/if}
      {/if}
      <label class="popover-row"><span>Interval</span>
        <select aria-label="Refresh interval" value={settings.intervalMs} onchange={(event) => onInterval(Number((event.currentTarget as HTMLSelectElement).value))}>
          <option value={1000}>1 sec</option><option value={2000}>2 sec</option><option value={5000}>5 sec</option>
        </select>
      </label>
      <label class="popover-check"><input type="checkbox" checked={settings.includeUdp} onchange={(event) => onUdp((event.currentTarget as HTMLInputElement).checked)} /><span>Include UDP</span></label>
      <label class="popover-check"><input type="checkbox" checked={settings.includeIpv6} onchange={(event) => onIpv6((event.currentTarget as HTMLInputElement).checked)} /><span>Include IPv6</span></label>
      <button class="pause-button" type="button" onclick={() => onPaused(!settings.paused)}>
        {settings.paused ? 'Resume monitoring' : 'Pause monitoring'}
      </button>
    </div>
  {/if}
</footer>
