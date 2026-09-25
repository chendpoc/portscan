<script lang="ts">
  import { formatBytes, formatCpuPercent, processKeyId } from '$lib/format'
  import { processGlyphUrl } from '$lib/process-glyph'
  import type { ProcessEntry, ProcessKey } from '$lib/types'

  type Props = {
    entries: ProcessEntry[]
    compact: boolean
    split: boolean
    selectedKey: ProcessKey | null
    processSort: 'cpu' | 'memory' | 'pid'
    sortDescending: boolean
    listenPortsFor: (key: ProcessKey) => number[]
    onSort: (column: 'cpu' | 'memory' | 'pid') => void
    onSelect: (entry: ProcessEntry) => void
    onPortChip: (entry: ProcessEntry, port: number, event: MouseEvent) => void
  }

  let {
    entries,
    compact,
    split,
    selectedKey,
    processSort,
    sortDescending,
    listenPortsFor,
    onSort,
    onSelect,
    onPortChip,
  }: Props = $props()

  function cpuClass(value: number | null): string {
    if (value == null) return ''
    if (value >= 20) return 'hot'
    return ''
  }

  function sortDir(column: 'cpu' | 'memory' | 'pid'): 'ascending' | 'descending' | 'none' {
    if (processSort !== column) return 'none'
    return sortDescending ? 'descending' : 'ascending'
  }
</script>

<table class="process-table" class:compact class:split>
  <colgroup>
    <col class="col-process" />
    {#if !split && !compact}<col class="col-pid" />{/if}
    <col class="col-cpu" />
    <col class="col-mem" />
    <col class="col-ports" />
    {#if !split}<col class="col-context" />{/if}
    <col class="col-chevron" />
  </colgroup>
  <thead>
    <tr>
      <th scope="col">Process</th>
      {#if !split && !compact}<th scope="col" aria-sort={sortDir('pid')}><button type="button" onclick={() => onSort('pid')}>PID</button></th>{/if}
      <th scope="col" aria-sort={sortDir('cpu')}><button type="button" onclick={() => onSort('cpu')}>CPU</button></th>
      <th scope="col" aria-sort={sortDir('memory')}><button type="button" onclick={() => onSort('memory')}>MEM</button></th>
      <th scope="col">Ports</th>
      {#if !split}<th scope="col">Project / CWD</th>{/if}
      <th scope="col" aria-hidden="true"></th>
    </tr>
  </thead>
  <tbody>
    {#each entries as entry (processKeyId(entry.key))}
      {@const ports = listenPortsFor(entry.key)}
      {@const selected = selectedKey && processKeyId(selectedKey) === processKeyId(entry.key)}
      <tr class:selected tabindex="0" onclick={() => onSelect(entry)} onkeydown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(entry) }
      }}>
        <td class="process-cell">
          <div class="cell-inner process-inner">
            <img class="process-glyph" src={processGlyphUrl(entry.name, entry.key.pid, entry.cwd.path)} alt="" aria-hidden="true" />
            <span class="process-name" title={entry.name}>{entry.name}</span>
          </div>
        </td>
        {#if !split && !compact}<td class="mono muted">{entry.key.pid}</td>{/if}
        <td class="mono cpu {cpuClass(entry.cpuPercent)}">{formatCpuPercent(entry.cpuPercent)}</td>
        <td class="mono">{formatBytes(entry.rssBytes)}</td>
        <td class="port-chips">
          <div class="cell-inner port-inner">
            {#each ports as port (port)}
              <button
                type="button"
                class="port-chip"
                onclick={(event) => { event.stopPropagation(); onPortChip(entry, port, event) }}
                onkeydown={(event) => event.stopPropagation()}
              >{port}</button>
            {:else}
              <span class="muted">—</span>
            {/each}
          </div>
        </td>
        {#if !split}
          <td class="mono context" title={entry.contextDisplay ?? ''}>{entry.contextDisplay ?? '—'}</td>
        {/if}
        <td class="chevron" aria-hidden="true">›</td>
      </tr>
    {/each}
  </tbody>
</table>
