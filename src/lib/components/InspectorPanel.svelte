<script lang="ts">
  import {
    formatBytes,
    formatCommand,
    formatCpuPercent,
    formatEndpoint,
    formatRelativeAge,
    formatUptime,
    pathEvidenceLabel,
    processKeyId,
  } from '$lib/format'
  import { processGlyphUrl } from '$lib/process-glyph'
  import type { InspectorEvidence } from '$lib/inspector-state.svelte'

  type Props = {
    evidence: InspectorEvidence
    compact: boolean
    nowMs: number
    processStale: boolean
    detailStale: boolean
    socketStale: boolean
    paused: boolean
    refreshing: boolean
    showAdvanced: boolean
    terminalLoading: boolean
    terminalError: string | null
    copyMessage: string | null
    onBack: () => void
    onClose: () => void
    onToggleAdvanced: () => void
    onTerminal: () => void
    onCopy: () => void
    portStateLabel: (entry: import('$lib/types').SocketEntry) => string
  }

  let {
    evidence,
    compact,
    nowMs,
    processStale,
    detailStale,
    socketStale,
    paused,
    refreshing,
    showAdvanced,
    terminalLoading,
    terminalError,
    copyMessage,
    onBack,
    onClose,
    onToggleAdvanced,
    onTerminal,
    onCopy,
    portStateLabel,
  }: Props = $props()

  const displayCommand = $derived.by(() => {
    if (evidence.detail?.command?.length) return formatCommand(evidence.detail.command)
    if (evidence.detailLoading) return evidence.detail?.command ? formatCommand(evidence.detail.command) : null
    if (evidence.detailError && evidence.detail?.command?.length) return formatCommand(evidence.detail.command)
    return null
  })

  const ancestryChain = $derived(
    evidence.detail?.ancestry?.map((node) => node.name).join(' → ') ?? '',
  )

  const verificationOk = $derived(
    !evidence.exited
      && !paused
      && !refreshing
      && !processStale
      && !detailStale
      && !socketStale
      && !evidence.detail?.ancestryIncomplete
      && !evidence.detailError,
  )

  const freshnessDetail = $derived.by(() => {
    if (evidence.exited) return 'Process exited or changed'
    if (refreshing) return 'Refreshing monitor cycle…'
    if (paused) return 'Paused monitoring'
    if (processStale || detailStale || socketStale || evidence.socketSourceFailed || evidence.processSourceFailed) {
      return 'Stale evidence'
    }
    if (evidence.detail?.ancestryIncomplete) return 'Ancestry incomplete'
    return '✓ Same process instance'
  })
</script>

<aside class="inspector-pane" aria-label="Process inspector">
  {#if compact}
    <button class="back-button" type="button" onclick={onBack}>← Back</button>
  {/if}
  <div class="inspector-title-row">
    <div class="inspector-title">
      {#if evidence.process}
        <img class="process-glyph" src={processGlyphUrl(evidence.process.name, evidence.key.pid, evidence.process.cwd.path)} alt="" aria-hidden="true" />
      {/if}
      <div class="inspector-title-text">
        <strong>{evidence.process?.name ?? (evidence.exited ? 'Process exited' : 'Unavailable')}</strong>
        <span class="mono muted">{evidence.key.pid}</span>
      </div>
    </div>
    <div class="inspector-title-actions">
      <button type="button" onclick={onCopy}>Copy</button>
      <button type="button" disabled={evidence.exited || terminalLoading || evidence.process?.cwd.state !== 'available'} onclick={onTerminal}>
        {terminalLoading ? 'Opening…' : 'Terminal'}
      </button>
      {#if !compact}
        <button type="button" class="icon-close" aria-label="Close inspector" onclick={onClose}>×</button>
      {/if}
    </div>
  </div>

  {#if evidence.exited}
    <p class="inspector-note">Process exited or changed. Last observations preserved; Terminal disabled.</p>
  {/if}

  <section class="inspector-block">
    <span class="label">Project / CWD</span>
    <code class="cwd-path">{pathEvidenceLabel(evidence.detail?.cwd ?? evidence.process?.cwd ?? { state: 'unavailable', path: null, message: null })}</code>
  </section>

  <div class="inspector-separator"></div>

  <div class="metric-row">
    <div><span>CPU</span><strong>{formatCpuPercent(evidence.process?.cpuPercent ?? null)}</strong></div>
    <div><span>MEM</span><strong>{formatBytes(evidence.process?.rssBytes ?? null)}</strong></div>
    <div><span>{evidence.exited ? 'Uptime at last observation' : 'Uptime'}</span><strong>{formatUptime(evidence.key.startSec, evidence.exited && evidence.processCapturedAt ? Date.parse(evidence.processCapturedAt) : nowMs)}</strong></div>
  </div>

  <div class="inspector-separator"></div>

  <section class="inspector-block">
    <span class="label">Command</span>
    <code>{#if evidence.detailLoading && !displayCommand}Reading…{:else if displayCommand}{displayCommand}{:else if evidence.detailError}<span class="error-inline">{evidence.detailError}</span>{:else}Unavailable from macOS{/if}</code>
  </section>

  {#if ancestryChain || evidence.detail?.ancestryIncomplete}
    <section class="inspector-block ancestry-horizontal">
      <span class="label">Parent process</span>
      {#if ancestryChain}
        <p class="mono ancestry-chain">{ancestryChain}</p>
      {:else}
        <p class="mono muted ancestry-chain">Ancestry incomplete or unavailable</p>
      {/if}
      {#if evidence.detail?.ancestryIncomplete}
        <p class="inspector-note">Ancestry chain incomplete — parent links may be missing.</p>
      {/if}
    </section>
  {/if}

  {#if evidence.endpoints.length}
    <div class="inspector-separator"></div>
    <div class="endpoints-heading">
      <span class="label">Sockets</span>
      <span class="muted">{evidence.endpoints.length} endpoints</span>
    </div>
    <ul class="endpoint-list">
      {#each evidence.endpoints as endpoint, index (index)}
        <li>
          <span class="mono endpoint-address">{formatEndpoint(endpoint.localAddress, endpoint.localPort)}</span>
          {#if endpoint.remoteAddress}
            <span class="mono muted endpoint-remote">→ {formatEndpoint(endpoint.remoteAddress, endpoint.remotePort)}</span>
          {/if}
          <span class="endpoint-state">{portStateLabel(endpoint)}</span>
        </li>
        <div class="inspector-separator"></div>
      {/each}
    </ul>
  {/if}

  <button class="text-button" type="button" onclick={onToggleAdvanced}>{showAdvanced ? 'Hide' : 'Show'} executable & identity</button>
  {#if showAdvanced}
    <dl class="inspector-grid advanced">
      <div><dt>Executable</dt><dd>{pathEvidenceLabel(evidence.detail?.executable ?? evidence.process?.executable ?? { state: 'unavailable', path: null, message: null })}</dd></div>
      <div><dt>Identity</dt><dd class="mono">{processKeyId(evidence.key)}</dd></div>
      <div><dt>Start time</dt><dd class="mono">{evidence.detail?.startTimeIso ?? 'Unavailable'}</dd></div>
      {#if evidence.detail?.ancestry?.length}
        <div><dt>Parent keys</dt><dd class="mono">{evidence.detail.ancestry.map((node) => `${node.name}:${processKeyId(node.key)}`).join(' · ')}</dd></div>
      {/if}
    </dl>
  {/if}

  <footer class="inspector-freshness">
    <span class:ok={verificationOk}>{freshnessDetail}</span>
    <span class="mono" title={evidence.detail?.verifiedAt ?? evidence.processCapturedAt ?? undefined}>
      {formatRelativeAge(evidence.detail?.verifiedAt ?? evidence.processCapturedAt, nowMs)}
    </span>
  </footer>
  <p class="inspector-source-lines">
    <span title={evidence.processCapturedAt ?? undefined}>
      Process {evidence.exited ? 'historical' : processStale || evidence.processSourceFailed ? 'stale/error' : 'ok'}
      ({formatRelativeAge(evidence.processCapturedAt, nowMs)})
    </span>
    ·
    <span title={evidence.endpointsCapturedAt ?? evidence.socketsCapturedAt ?? undefined}>
      Sockets {evidence.exited ? 'historical' : socketStale || evidence.socketSourceFailed ? 'stale/error' : 'ok'}
      ({formatRelativeAge(evidence.endpointsCapturedAt ?? evidence.socketsCapturedAt, nowMs)})
    </span>
    ·
    <span title={evidence.detail?.verifiedAt ?? undefined}>
      Detail {evidence.exited ? 'historical' : detailStale || evidence.detailError ? 'stale/error' : 'ok'}
      ({formatRelativeAge(evidence.detail?.verifiedAt, nowMs)})
    </span>
  </p>
  {#if terminalError}<p class="inspector-note error">{terminalError}</p>{/if}
  {#if copyMessage}<p class="inspector-note">{copyMessage}</p>{/if}
</aside>
