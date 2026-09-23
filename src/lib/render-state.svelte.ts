import { isTauri } from '@tauri-apps/api/core'
import { listen, type UnlistenFn } from '@tauri-apps/api/event'
import {
  diagnoseLsof,
  getSettings,
  refreshNow as invokeRefreshNow,
  updateSettings,
} from './api'
import { fixtureSnapshot, stateLabel } from './format'
import type {
  LsofSample,
  Protocol,
  RefreshSettings,
  RenderStatus,
  SocketEntry,
  SocketSnapshot,
  SocketState,
} from './types'

let snapshot = $state<SocketSnapshot | null>(null)
let status = $state<RenderStatus>('loading')
let error = $state<string | null>(null)
let query = $state('')
let protocol = $state<'all' | Protocol>('all')
let connectionState = $state<'all' | SocketState>('all')
let settings = $state<RefreshSettings>({
  intervalMs: 2000,
  paused: false,
  includeUdp: true,
  includeIpv6: true,
})
let preview = $state(false)
let refreshing = $state(false)
let diagnosing = $state(false)
let lsof = $state<LsofSample | null>(null)

let unlistenSnapshot: UnlistenFn | null = null
let unlistenError: UnlistenFn | null = null

const visible = $derived.by(() => {
  const sockets = snapshot?.sockets ?? []
  return sockets.filter((entry) => matches(entry, query, protocol, connectionState))
})

const counts = $derived.by(() => {
  const sockets = snapshot?.sockets ?? []
  let established = 0
  let listen = 0
  let udp = 0
  for (const entry of sockets) {
    if (entry.state === 'established') established += 1
    if (entry.state === 'listen') listen += 1
    if (entry.protocol === 'udp') udp += 1
  }
  return { total: sockets.length, established, listen, udp }
})

function matches(
  entry: SocketEntry,
  needleText: string,
  protocolFilter: 'all' | Protocol,
  stateFilter: 'all' | SocketState,
): boolean {
  if (protocolFilter !== 'all' && entry.protocol !== protocolFilter) return false
  if (stateFilter !== 'all' && entry.state !== stateFilter) return false
  const needle = needleText.trim().toLowerCase()
  if (!needle) return true
  const haystack = [
    entry.processName ?? '',
    entry.pid?.toString() ?? '',
    entry.protocol,
    entry.localAddress,
    String(entry.localPort),
    entry.remoteAddress ?? '',
    entry.remotePort?.toString() ?? '',
    entry.state,
    stateLabel(entry.state),
  ]
    .join(' ')
    .toLowerCase()
  return haystack.includes(needle)
}

function errorText(cause: unknown): string {
  if (cause instanceof Error) return cause.message
  return String(cause)
}

async function commit(next: RefreshSettings) {
  const previous = settings
  settings = next
  if (next.paused) status = 'paused'
  else if (status === 'paused') status = snapshot ? 'live' : 'loading'
  if (preview) return
  try {
    settings = await updateSettings(next)
  } catch (cause) {
    settings = previous
    error = errorText(cause)
    status = 'error'
  }
}

async function refreshNow() {
  if (preview) {
    snapshot = fixtureSnapshot()
    status = settings.paused ? 'paused' : 'live'
    return
  }
  refreshing = true
  try {
    snapshot = await invokeRefreshNow()
    error = null
    status = settings.paused ? 'paused' : 'live'
  } catch (cause) {
    error = errorText(cause)
    status = 'error'
  } finally {
    refreshing = false
  }
}

async function diagnose() {
  if (preview) {
    lsof = { lineCount: snapshot?.sockets.length ?? 0 }
    return
  }
  diagnosing = true
  try {
    lsof = await diagnoseLsof()
  } catch (cause) {
    error = errorText(cause)
    status = 'error'
  } finally {
    diagnosing = false
  }
}

async function stop() {
  unlistenSnapshot?.()
  unlistenError?.()
  unlistenSnapshot = null
  unlistenError = null
}

async function start() {
  await stop()
  if (!isTauri()) {
    preview = true
    snapshot = fixtureSnapshot()
    status = 'live'
    error = null
    return
  }

  preview = false
  status = 'loading'
  try {
    settings = await getSettings()
    unlistenSnapshot = await listen<SocketSnapshot>('snapshot', (event) => {
      snapshot = event.payload
      error = null
      status = settings.paused ? 'paused' : 'live'
    })
    unlistenError = await listen<string>('snapshot-error', (event) => {
      error = event.payload
      status = 'error'
    })
    await refreshNow()
  } catch (cause) {
    error = errorText(cause)
    status = 'error'
  }
}

export const renderState = {
  get snapshot() {
    return snapshot
  },
  get visible() {
    return visible
  },
  get status() {
    return status
  },
  get error() {
    return error
  },
  get query() {
    return query
  },
  get protocol() {
    return protocol
  },
  get connectionState() {
    return connectionState
  },
  get settings() {
    return settings
  },
  get counts() {
    return counts
  },
  get preview() {
    return preview
  },
  get refreshing() {
    return refreshing
  },
  get diagnosing() {
    return diagnosing
  },
  get lsof() {
    return lsof
  },
  setQuery(value: string) {
    query = value
  },
  setProtocol(value: 'all' | Protocol) {
    protocol = value
  },
  setConnectionState(value: 'all' | SocketState) {
    connectionState = value
  },
  setPaused(paused: boolean) {
    return commit({ ...settings, paused })
  },
  setInterval(intervalMs: number) {
    return commit({ ...settings, intervalMs })
  },
  setIncludeUdp(includeUdp: boolean) {
    return commit({ ...settings, includeUdp })
  },
  setIncludeIpv6(includeIpv6: boolean) {
    return commit({ ...settings, includeIpv6 })
  },
  refreshNow,
  diagnose,
  start,
  stop,
}

export type RenderState = typeof renderState
