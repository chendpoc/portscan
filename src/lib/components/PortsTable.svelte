<script lang="ts">
  import { formatEndpoint, processKeyId, rowKey, stateClass, stateLabel } from '$lib/format'
  import type { SocketEntry } from '$lib/types'

  type Props = {
    entries: SocketEntry[]
    contextFor: (key: NonNullable<SocketEntry['processKey']>) => string
    showRemote: boolean
    onSelect: (entry: SocketEntry) => void
    portStateLabel: (entry: SocketEntry) => string
  }

  let { entries, contextFor, showRemote, onSelect, portStateLabel }: Props = $props()
</script>

<table class="ports-table">
  <thead>
    <tr>
      <th scope="col">Port</th>
      <th scope="col">Process</th>
      <th scope="col">PID</th>
      <th scope="col">State</th>
      <th scope="col">Address</th>
      {#if showRemote}<th scope="col">Remote</th>{/if}
      <th scope="col">Project / CWD</th>
    </tr>
  </thead>
  <tbody>
    {#each entries as entry, index (rowKey(entry, index))}
      <tr tabindex="0" onclick={() => onSelect(entry)} onkeydown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(entry) }
      }}>
        <td class="mono port">{entry.localPort}</td>
        <td class="process-name">{entry.processName ?? 'Unknown owner'}</td>
        <td class="mono muted">{entry.pid ?? '—'}</td>
        <td class="state {stateClass(entry.state)}">{portStateLabel(entry)}</td>
        <td class="mono address" title={formatEndpoint(entry.localAddress, entry.localPort)}>{entry.localAddress}</td>
        {#if showRemote}
          <td class="mono remote">{entry.remoteAddress ? formatEndpoint(entry.remoteAddress, entry.remotePort) : '—'}</td>
        {/if}
        <td class="mono context">{entry.processKey ? contextFor(entry.processKey) : 'Unverified owner'}</td>
      </tr>
    {/each}
  </tbody>
</table>
