<script lang="ts">
  import { onMount } from 'svelte'
  import { openProcessTerminal } from '$lib/api'
  import { buildInspectorReport } from '$lib/copy-report'
  import AppToolbar from '$lib/components/AppToolbar.svelte'
  import InspectorPanel from '$lib/components/InspectorPanel.svelte'
  import PortsTable from '$lib/components/PortsTable.svelte'
  import ProcessTable from '$lib/components/ProcessTable.svelte'
  import SearchSummary from '$lib/components/SearchSummary.svelte'
  import StatusFooter from '$lib/components/StatusFooter.svelte'
  import { processKeyId, stateClass, stateLabel } from '$lib/format'
  import { inspectorState } from '$lib/inspector-state.svelte'
  import { renderState } from '$lib/render-state.svelte'
  import type { ProcessEntry, SocketEntry } from '$lib/types'

  let settingsOpen = $state(false)
  let compact = $state(false)
  let showAdvanced = $state(false)
  let terminalError = $state<string | null>(null)
  let terminalLoading = $state(false)
  let copyMessage = $state<string | null>(null)

  const inspectorOpen = $derived(inspectorState.selectedKey != null)
  const showMasterOnly = $derived(compact && inspectorOpen)
  const evidence = $derived.by(() => {
    const key = inspectorState.selectedKey
    if (!key) return null
    return inspectorState.evidence(
      renderState.findProcess(key),
      renderState.endpointsFor(key),
      renderState.detailStale,
      renderState.processes?.capturedAt ?? null,
      renderState.sockets?.capturedAt ?? null,
    )
  })

  onMount(() => {
    const media = window.matchMedia('(max-width: 759px)')
    const update = () => { compact = media.matches }
    update()
    media.addEventListener('change', update)
    void renderState.start()
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && inspectorState.selectedKey) closeDetail()
    }
    window.addEventListener('keydown', onKey)
    return () => {
      media.removeEventListener('change', update)
      window.removeEventListener('keydown', onKey)
      void renderState.stop()
    }
  })

  function captureContext() {
    return {
      processCapturedAt: renderState.processes?.capturedAt ?? null,
      endpointsCapturedAt: renderState.sockets?.capturedAt ?? null,
      socketsFailed: renderState.socketError != null,
      processesFailed: renderState.processError != null,
    }
  }

  function selectProcess(entry: ProcessEntry) {
    terminalError = null
    copyMessage = null
    const capture = captureContext()
    inspectorState.select(
      entry.key,
      entry,
      renderState.endpointsFor(entry.key),
      false,
      capture.processCapturedAt,
      capture.endpointsCapturedAt,
      capture.socketsFailed,
      capture.processesFailed,
    )
  }

  function selectPort(entry: SocketEntry) {
    if (!entry.processKey) return
    const live = renderState.findProcess(entry.processKey)
    if (live) {
      selectProcess(live)
      return
    }
    terminalError = null
    copyMessage = null
    const capture = captureContext()
    inspectorState.select(
      entry.processKey,
      null,
      renderState.endpointsFor(entry.processKey),
      true,
      capture.processCapturedAt,
      capture.endpointsCapturedAt,
      capture.socketsFailed,
      capture.processesFailed,
    )
  }

  function onPortChip(entry: ProcessEntry, port: number) {
    terminalError = null
    copyMessage = null
    renderState.scopePorts(entry.key, port)
    const capture = captureContext()
    inspectorState.select(
      entry.key,
      entry,
      renderState.endpointsFor(entry.key),
      false,
      capture.processCapturedAt,
      capture.endpointsCapturedAt,
      capture.socketsFailed,
      capture.processesFailed,
    )
  }

  function closeDetail() {
    inspectorState.close()
    terminalError = null
    copyMessage = null
  }

  async function copyReport() {
    const ev = evidence
    if (!ev) return
    const selectionId = processKeyId(ev.key)
    const text = buildInspectorReport({
      process: ev.process ?? undefined,
      detail: ev.detail,
      key: ev.key,
      exited: ev.exited,
      endpoints: ev.endpoints,
      processCapturedAt: ev.processCapturedAt,
      endpointsCapturedAt: ev.endpointsCapturedAt,
      processStale: renderState.processStale || ev.exited,
      socketStale: renderState.socketStale || ev.exited,
      detailStale: renderState.detailStale || ev.exited,
      processError: renderState.processError,
      socketError: renderState.socketError,
      detailError: ev.detailError,
    })
    try {
      await navigator.clipboard.writeText(text)
      if (inspectorState.selectedKey && processKeyId(inspectorState.selectedKey) === selectionId) {
        copyMessage = 'Copied'
      }
    } catch {
      if (inspectorState.selectedKey && processKeyId(inspectorState.selectedKey) === selectionId) {
        copyMessage = 'Copy failed'
      }
    }
  }

  async function openTerminal() {
    const key = inspectorState.selectedKey
    if (!key || evidence?.exited) return
    const selectionId = processKeyId(key)
    terminalLoading = true
    terminalError = null
    try {
      await openProcessTerminal(key)
    } catch (cause) {
      if (inspectorState.selectedKey && processKeyId(inspectorState.selectedKey) === selectionId) {
        terminalError = String(cause)
      }
    } finally {
      if (inspectorState.selectedKey && processKeyId(inspectorState.selectedKey) === selectionId) {
        terminalLoading = false
      }
    }
  }

  function inspectorSelectionLabel(): string {
    const key = inspectorState.selectedKey
    if (!key) return ''
    const name = renderState.findProcess(key)?.name ?? evidence?.process?.name
    return name ? ` · ${name} (PID ${key.pid})` : ` · PID ${key.pid}`
  }

  function portStateLabel(entry: SocketEntry): string {
    const proto = entry.protocol.toUpperCase()
    if (entry.protocol === 'udp' && entry.state === 'none') return `${proto} BOUND`
    return `${proto} ${stateLabel(entry.state)}`
  }
</script>

<div class="app-shell" class:preview={renderState.preview}>
  <main class="utility-window" aria-label="PortMaster process-first runtime inspector">
    <AppToolbar
      preview={renderState.preview}
      view={renderState.view}
      query={renderState.query}
      refreshing={renderState.refreshing}
      onQuery={(value) => renderState.setQuery(value)}
      onClear={() => renderState.clearQuery()}
      onView={(value) => renderState.setView(value)}
      onRefresh={() => renderState.refreshNow()}
    />

    {#if renderState.error}
      <p class="error-banner" role="alert">
        {renderState.view === 'processes' ? 'Process' : 'Socket'} update failed: {renderState.error}.
        <button type="button" onclick={() => renderState.refreshNow()}>Retry</button>
      </p>
    {/if}

    <div class="content-shell" class:split={inspectorOpen && !showMasterOnly}>
        <section class="master-pane" class:hidden={showMasterOnly} aria-hidden={showMasterOnly} aria-label="Process and port lists">
          <div class="view-pane" class:hidden={renderState.view !== 'processes'} aria-hidden={renderState.view !== 'processes'}>
            <SearchSummary count={renderState.matchingProcessCount} query={renderState.query} />
            <div class="table-scroll" data-view="processes">
              {#if !renderState.processes && renderState.status === 'loading'}
                <p class="empty-state">Reading processes…</p>
              {:else if !renderState.processes}
                <p class="empty-state">Process inventory unavailable.</p>
              {:else}
                <ProcessTable
                  entries={renderState.visibleProcesses}
                  compact={compact}
                  split={inspectorOpen && !compact}
                  selectedKey={renderState.view === 'processes' ? inspectorState.selectedKey : null}
                  processSort={renderState.processSort}
                  sortDescending={renderState.sortDescending}
                  listenPortsFor={(key) => renderState.listenPortsFor(key)}
                  onSort={(column) => renderState.setProcessSort(column)}
                  onSelect={selectProcess}
                  onPortChip={onPortChip}
                />
                {#if renderState.visibleProcesses.length === 0}<p class="empty-state">No matching processes</p>{/if}
              {/if}
            </div>
          </div>
          <div class="view-pane" class:hidden={renderState.view !== 'ports'} aria-hidden={renderState.view !== 'ports'}>
            {#if renderState.portScope}
              <div class="scope-bar">
                <span>Ports for {renderState.findProcess(renderState.portScope)?.name ?? `PID ${renderState.portScope.pid}`}</span>
                <button type="button" onclick={() => renderState.clearPortScope()}>Clear scope ×</button>
              </div>
            {/if}
            <div class="table-scroll" data-view="ports">
              {#if !renderState.sockets && renderState.status === 'loading'}
                <p class="empty-state">Reading local sockets…</p>
              {:else if !renderState.sockets}
                <p class="empty-state">Socket inventory unavailable.</p>
              {:else}
                <PortsTable
                  entries={renderState.visiblePorts}
                  contextFor={(key) => renderState.contextForProcess(key)}
                  showRemote={renderState.portsFilter === 'all'}
                  onSelect={selectPort}
                  {portStateLabel}
                />
                {#if renderState.visiblePorts.length === 0}<p class="empty-state">No matching ports</p>{/if}
              {/if}
            </div>
          </div>
        </section>

      {#if evidence}
        <InspectorPanel
          {evidence}
          compact={showMasterOnly}
          nowMs={renderState.nowMs}
          detailStale={renderState.detailStale}
          processStale={renderState.processStale}
          socketStale={renderState.socketStale}
          paused={renderState.settings.paused}
          refreshing={renderState.refreshing}
          {showAdvanced}
          {terminalLoading}
          {terminalError}
          {copyMessage}
          onBack={closeDetail}
          onClose={closeDetail}
          onToggleAdvanced={() => (showAdvanced = !showAdvanced)}
          onTerminal={openTerminal}
          onCopy={copyReport}
          {portStateLabel}
        />
      {/if}
    </div>

    <StatusFooter
      view={renderState.view}
      status={renderState.status}
      settings={renderState.settings}
      capturedAt={(renderState.view === 'processes' ? renderState.processes?.capturedAt : renderState.sockets?.capturedAt) ?? ''}
      preview={renderState.preview}
      summary={renderState.view === 'processes'
        ? `${renderState.processCounts.total} processes${inspectorSelectionLabel()}`
        : `${renderState.portCounts.listeners} listeners · ${renderState.portCounts.all} sockets${inspectorSelectionLabel()}`}
      connectionState={renderState.connectionState}
      onConnectionState={(value) => renderState.setConnectionState(value as import('$lib/types').SocketState | 'all')}
      open={settingsOpen}
      onToggle={() => (settingsOpen = !settingsOpen)}
      onInterval={(ms) => renderState.setInterval(ms)}
      onUdp={(value) => renderState.setIncludeUdp(value)}
      onIpv6={(value) => renderState.setIncludeIpv6(value)}
      onPaused={(value) => renderState.setPaused(value)}
      processFilter={renderState.processFilter}
      onProcessFilter={(value) => renderState.setProcessFilter(value)}
      protocol={renderState.protocol}
      onProtocol={(value) => renderState.setProtocol(value)}
      portsFilter={renderState.portsFilter}
      onPortsFilter={(value) => renderState.setPortsFilter(value)}
    />
  </main>
</div>
