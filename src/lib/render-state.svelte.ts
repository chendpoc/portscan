import { isTauri } from '@tauri-apps/api/core'
import { listen, type UnlistenFn } from '@tauri-apps/api/event'
import { getMonitorState, getSettings, requestRefresh, updateSettings } from './api'
import { fixtureMonitorState, processKeyId } from './format'
import { inspectorState } from './inspector-state.svelte'
import {
  filterPorts,
  filterProcesses,
  isSnapshotStale,
  listenerPortFilter,
  listenPortsByProcess,
  type ProcessFilter,
  type ProcessSort,
} from './monitor-logic'
import {
  applyBootstrapMonitorState,
  applyProcessSnapshot,
  applySocketSnapshot,
  monitorCycleGeneration,
  reduceProcessErrorEvent,
  reduceRefreshComplete,
  reduceRefreshFatal,
  reduceSocketErrorEvent,
  shouldClearFatalError,
  type SourceGenerationState,
} from './render-events'
import type { RefreshFatal } from './types'
import type {
  MonitorState,
  PortsFilter,
  PrimaryView,
  ProcessEntry,
  ProcessKey,
  ProcessSnapshot,
  Protocol,
  RefreshSettings,
  RenderStatus,
  SnapshotError,
  SocketSnapshot,
  SocketState,
} from './types'

let monitor = $state<MonitorState>({ processes: null, sockets: null, processError: null, socketError: null })
let fatalError = $state<string | null>(null)
let fatalErrorGeneration = $state(0)
let processQuery = $state('')
let portsQuery = $state('')
let view = $state<PrimaryView>('processes')
let portsFilter = $state<PortsFilter>('listeners')
let processFilter = $state<ProcessFilter>('all')
let protocol = $state<'all' | Protocol>('all')
let connectionState = $state<'all' | SocketState>('all')
let processSort = $state<ProcessSort>('cpu')
let sortDescending = $state(true)
let portScope = $state<ProcessKey | null>(null)
let settings = $state<RefreshSettings>({ intervalMs: 2000, paused: false, includeUdp: true, includeIpv6: true })
let preview = $state(false)
let refreshing = $state(false)
let nowMs = $state(Date.now())
let unlisteners: UnlistenFn[] = []
let clockTimer: ReturnType<typeof setInterval> | null = null
let generationState = $state<SourceGenerationState>({ processSeen: -1, socketSeen: -1 })
let cycleSeen = $state(-1)

const listenPortSets = $derived.by(() => listenPortsByProcess(monitor.sockets?.sockets ?? []))

const contextPathsByProcess = $derived.by(() => {
  const map = new Map<string, string>()
  for (const entry of monitor.processes?.entries ?? []) {
    const paths = [entry.cwd.path, entry.executable.path, entry.contextDisplay]
      .filter(Boolean)
      .join(' ')
    map.set(processKeyId(entry.key), paths)
  }
  return map
})

const contextDisplayByProcess = $derived.by(() => {
  const map = new Map<string, string>()
  for (const entry of monitor.processes?.entries ?? []) {
    map.set(processKeyId(entry.key), entry.contextDisplay ?? entry.cwd.path ?? '—')
  }
  return map
})

const visibleProcesses = $derived.by(() =>
  filterProcesses(
    monitor.processes?.entries ?? [],
    processQuery,
    listenPortSets,
    processFilter,
    processSort,
    sortDescending,
  ),
)

const processCounts = $derived.by(() => {
  const entries = monitor.processes?.entries ?? []
  return {
    total: entries.length,
    running: entries.filter((entry) => entry.status === 'running').length,
    withListeners: monitor.sockets && !monitor.socketError
      ? entries.filter((entry) => (listenPortSets.get(processKeyId(entry.key))?.size ?? 0) > 0).length
      : null,
  }
})

const portCounts = $derived.by(() => {
  const sockets = monitor.sockets?.sockets ?? []
  return { listeners: sockets.filter((entry) => listenerPortFilter(entry)).length, all: sockets.length }
})

const visiblePorts = $derived.by(() =>
  filterPorts(
    monitor.sockets?.sockets ?? [],
    portsQuery,
    contextPathsByProcess,
    portsFilter,
    protocol,
    connectionState,
    portScope,
  ),
)

const processStale = $derived(isSnapshotStale(
  monitor.processes?.capturedAt,
  settings.intervalMs,
  monitor.processError != null,
  nowMs,
))

const socketStale = $derived(isSnapshotStale(
  monitor.sockets?.capturedAt,
  settings.intervalMs,
  monitor.socketError != null,
  nowMs,
))

const detailStale = $derived(isSnapshotStale(
  inspectorState.detailCapturedAt ?? undefined,
  settings.intervalMs,
  inspectorState.detailError != null,
  nowMs,
))

function errorText(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause)
}

function endpointsForKey(key: ProcessKey) {
  return (monitor.sockets?.sockets ?? []).filter(
    (entry) => entry.processKey && processKeyId(entry.processKey) === processKeyId(key),
  )
}

function syncInspectorFromMonitor(snapshot?: ProcessSnapshot) {
  const findProcess = (lookup: ProcessKey) =>
    (snapshot ?? monitor.processes)?.entries.find(
      (entry) => processKeyId(entry.key) === processKeyId(lookup),
    )
  inspectorState.syncLastGood(
    findProcess,
    endpointsForKey,
    monitor.processes?.capturedAt ?? null,
    monitor.sockets?.capturedAt ?? null,
    monitor.socketError != null,
    monitor.processError != null,
  )
}

function acceptProcess(snapshot: ProcessSnapshot) {
  const applied = applyProcessSnapshot(generationState, snapshot)
  if (!applied.accepted) return
  generationState = applied.state
  monitor.processes = snapshot
  monitor.processError = null
  syncInspectorFromMonitor(snapshot)
}

function acceptSockets(snapshot: SocketSnapshot) {
  const applied = applySocketSnapshot(generationState, snapshot)
  if (!applied.accepted) return
  generationState = applied.state
  monitor.sockets = snapshot
  monitor.socketError = null
  syncInspectorFromMonitor()
}

async function commit(next: RefreshSettings) {
  const previous = settings
  settings = next
  if (preview) return
  try {
    settings = await updateSettings(next)
  } catch (cause) {
    settings = previous
    fatalError = errorText(cause)
  }
}

async function refreshNow() {
  if (preview) {
    monitor = fixtureMonitorState()
    nowMs = Date.now()
    return
  }
  refreshing = true
  try {
    await requestRefresh()
  } catch (cause) {
    refreshing = false
    fatalError = errorText(cause)
  }
}

function setView(next: PrimaryView) {
  if (view === next) return
  view = next
  inspectorState.switchView(next)
}

function scopePorts(key: ProcessKey, port?: number) {
  portScope = key
  portsFilter = 'listeners'
  if (port != null) portsQuery = String(port)
  setView('ports')
}

function clearPortScope() {
  portScope = null
}

function startClock() {
  if (clockTimer) clearInterval(clockTimer)
  clockTimer = setInterval(() => { nowMs = Date.now() }, 1000)
}

async function stop() {
  if (clockTimer) clearInterval(clockTimer)
  clockTimer = null
  for (const unlisten of unlisteners) unlisten()
  unlisteners = []
}

async function start() {
  await stop()
  startClock()
  if (!isTauri()) {
    preview = true
    inspectorState.setPreview(true)
    monitor = fixtureMonitorState()
    fatalError = null
    generationState = { processSeen: monitor.processes?.generation ?? 1, socketSeen: monitor.sockets?.generation ?? 1 }
    cycleSeen = monitorCycleGeneration(monitor)
    return
  }

  preview = false
  inspectorState.setPreview(false)
  generationState = { processSeen: -1, socketSeen: -1 }
  cycleSeen = -1
  try {
    settings = await getSettings()
    unlisteners.push(await listen<ProcessSnapshot>('process-snapshot', (event) => acceptProcess(event.payload)))
    unlisteners.push(await listen<SocketSnapshot>('snapshot', (event) => acceptSockets(event.payload)))
    unlisteners.push(await listen<SnapshotError>('process-error', (event) => {
      const reduced = reduceProcessErrorEvent(generationState, event.payload)
      generationState = reduced.state
      if (reduced.message != null) monitor.processError = reduced.message
    }))
    unlisteners.push(await listen<SnapshotError>('snapshot-error', (event) => {
      const reduced = reduceSocketErrorEvent(generationState, event.payload)
      generationState = reduced.state
      if (reduced.message != null) monitor.socketError = reduced.message
    }))
    unlisteners.push(await listen<number>('refresh-complete', (event) => {
      const reduced = reduceRefreshComplete(cycleSeen, event.payload, Math.max(generationState.processSeen, generationState.socketSeen))
      cycleSeen = reduced.cycleSeen
      if (!reduced.accepted) return
      refreshing = false
      if (shouldClearFatalError(fatalErrorGeneration, event.payload)) {
        fatalError = null
      }
      syncInspectorFromMonitor()
      inspectorState.noteRefreshComplete(event.payload)
    }))
    unlisteners.push(await listen<RefreshFatal>('refresh-fatal', (event) => {
      const reduced = reduceRefreshFatal(cycleSeen, event.payload, Math.max(generationState.processSeen, generationState.socketSeen))
      cycleSeen = reduced.cycleSeen
      if (!reduced.accepted) return
      refreshing = false
      fatalError = reduced.message
      fatalErrorGeneration = event.payload.generation
    }))
    const initial = await getMonitorState()
    const merged = applyBootstrapMonitorState(generationState, monitor, initial)
    generationState = merged.state
    monitor = { ...monitor, ...merged.monitor }
    cycleSeen = Math.max(cycleSeen, monitorCycleGeneration(initial))
    if (monitor.processes) syncInspectorFromMonitor(monitor.processes)
    await refreshNow()
  } catch (cause) {
    fatalError = errorText(cause)
  }
}

export const renderState = {
  get processes() { return monitor.processes },
  get sockets() { return monitor.sockets },
  get socketError() { return monitor.socketError },
  get processError() { return monitor.processError },
  get view() { return view },
  get portsFilter() { return portsFilter },
  get processFilter() { return processFilter },
  get protocol() { return protocol },
  get connectionState() { return connectionState },
  get portScope() { return portScope },
  get processStale() { return processStale },
  get socketStale() { return socketStale },
  get detailStale() { return detailStale },
  get nowMs() { return nowMs },
  get error() {
    return fatalError ?? (view === 'processes' ? monitor.processError : monitor.socketError)
  },
  get status(): RenderStatus {
    const stale = view === 'processes' ? processStale : socketStale
    if (settings.paused) return stale ? 'stale' : 'paused'
    if (this.error) return stale ? 'stale' : 'error'
    if (stale) return 'stale'
    if (refreshing) return 'live'
    return view === 'processes'
      ? (monitor.processes ? 'live' : 'loading')
      : (monitor.sockets ? 'live' : 'loading')
  },
  get query() { return view === 'ports' ? portsQuery : processQuery },
  get processSort() { return processSort },
  get sortDescending() { return sortDescending },
  get settings() { return settings },
  get processCounts() { return processCounts },
  get portCounts() { return portCounts },
  get visibleProcesses() { return visibleProcesses },
  get visiblePorts() { return visiblePorts },
  get listenPortSets() { return listenPortSets },
  get matchingProcessCount() { return visibleProcesses.length },
  listenPortsFor(key: ProcessKey) {
    return [...(listenPortSets.get(processKeyId(key)) ?? [])].sort((a, b) => a - b)
  },
  contextForProcess(key: ProcessKey) {
    return contextDisplayByProcess.get(processKeyId(key)) ?? '—'
  },
  findProcess(key: ProcessKey): ProcessEntry | undefined {
    return monitor.processes?.entries.find((entry) => processKeyId(entry.key) === processKeyId(key))
  },
  endpointsFor(key: ProcessKey) {
    return endpointsForKey(key)
  },
  get preview() { return preview },
  get refreshing() { return refreshing },
  setQuery(value: string) {
    if (view === 'ports') portsQuery = value
    else processQuery = value
  },
  clearQuery() {
    if (view === 'ports') portsQuery = ''
    else processQuery = ''
  },
  setView,
  setPortsFilter(value: PortsFilter) { portsFilter = value },
  setProcessFilter(value: ProcessFilter) { processFilter = value },
  setProtocol(value: 'all' | Protocol) { protocol = value },
  setConnectionState(value: 'all' | SocketState) { connectionState = value },
  setProcessSort(value: ProcessSort) {
    if (processSort === value) sortDescending = !sortDescending
    else { processSort = value; sortDescending = value !== 'pid' }
  },
  scopePorts,
  clearPortScope,
  setPaused(paused: boolean) { return commit({ ...settings, paused }) },
  setInterval(intervalMs: number) { return commit({ ...settings, intervalMs }) },
  setIncludeUdp(includeUdp: boolean) { return commit({ ...settings, includeUdp }) },
  setIncludeIpv6(includeIpv6: boolean) { return commit({ ...settings, includeIpv6 }) },
  refreshNow,
  start,
  stop,
}

export type RenderState = typeof renderState
