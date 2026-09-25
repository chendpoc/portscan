import { processKeyId } from './format'
import type { ProcessEntry, ProcessKey, SocketEntry, SocketState } from './types'

export type ProcessSort = 'cpu' | 'memory' | 'pid'
export type ProcessFilter = 'all' | 'running' | 'with_listeners'

export function staleThresholdMs(intervalMs: number): number {
  return Math.max(intervalMs * 3, 5000)
}

export function isSnapshotStale(
  capturedAt: string | undefined,
  intervalMs: number,
  sourceFailed: boolean,
  nowMs: number,
): boolean {
  if (sourceFailed) return true
  if (!capturedAt) return true
  const age = nowMs - new Date(capturedAt).getTime()
  return age > staleThresholdMs(intervalMs)
}

export function parseNumericQuery(raw: string): number | null {
  const trimmed = raw.trim()
  if (!/^\d+$/.test(trimmed)) return null
  const value = Number(trimmed)
  return Number.isSafeInteger(value) ? value : null
}

export function matchesProcessSearch(
  entry: ProcessEntry,
  query: string,
  listenPortsForEntry: Iterable<number>,
): boolean {
  const trimmed = query.trim()
  if (!trimmed) return true
  const numeric = parseNumericQuery(trimmed)
  if (numeric != null) {
    if (entry.key.pid === numeric) return true
    for (const port of listenPortsForEntry) {
      if (port === numeric) return true
    }
    return false
  }
  const needle = trimmed.toLowerCase()
  const haystacks = [
    entry.name,
    entry.contextDisplay ?? '',
    entry.cwd.path ?? '',
    entry.executable.path ?? '',
  ]
  return haystacks.some((value) => value.toLowerCase().includes(needle))
}

export function matchesPortSearch(
  entry: SocketEntry,
  query: string,
  contextPaths: Map<string, string>,
): boolean {
  const trimmed = query.trim()
  if (!trimmed) return true
  const numeric = parseNumericQuery(trimmed)
  if (numeric != null) {
    if (entry.localPort === numeric) return true
    if (entry.pid === numeric) return true
    return false
  }
  const needle = trimmed.toLowerCase()
  const context = entry.processKey ? contextPaths.get(processKeyId(entry.processKey)) ?? '' : ''
  const haystacks = [
    entry.processName ?? '',
    entry.localAddress,
    String(entry.localPort),
    context,
  ]
  return haystacks.some((value) => value.toLowerCase().includes(needle))
}

export function compareProcess(
  a: ProcessEntry,
  b: ProcessEntry,
  by: ProcessSort,
  descending: boolean,
): number {
  if (by === 'pid') return (a.key.pid - b.key.pid) * (descending ? -1 : 1)
  const left = by === 'cpu' ? a.cpuPercent : a.rssBytes
  const right = by === 'cpu' ? b.cpuPercent : b.rssBytes
  if (left == null && right != null) return 1
  if (left != null && right == null) return -1
  const delta = (left ?? 0) - (right ?? 0)
  return delta === 0 ? a.key.pid - b.key.pid : delta * (descending ? -1 : 1)
}

export function listenerPortFilter(entry: SocketEntry): boolean {
  if (entry.protocol === 'tcp') return entry.state === 'listen'
  return entry.protocol === 'udp' && entry.state === 'none'
}

export function listenPortsByProcess(sockets: SocketEntry[]): Map<string, Set<number>> {
  const map = new Map<string, Set<number>>()
  for (const entry of sockets) {
    if (!entry.processKey) continue
    if (entry.state !== 'listen' && !(entry.protocol === 'udp' && entry.state === 'none')) continue
    const id = processKeyId(entry.processKey)
    const set = map.get(id) ?? new Set<number>()
    set.add(entry.localPort)
    map.set(id, set)
  }
  return map
}

export function filterProcesses(
  entries: ProcessEntry[],
  query: string,
  listenPortSets: Map<string, Set<number>>,
  processFilter: ProcessFilter,
  sort: ProcessSort,
  descending: boolean,
): ProcessEntry[] {
  return entries
    .filter((entry) => {
      if (processFilter === 'running' && entry.status !== 'running') return false
      if (processFilter === 'with_listeners') {
        const ports = listenPortSets.get(processKeyId(entry.key))
        if (!ports || ports.size === 0) return false
      }
      const ports = listenPortSets.get(processKeyId(entry.key)) ?? []
      return matchesProcessSearch(entry, query, ports)
    })
    .sort((a, b) => compareProcess(a, b, sort, descending))
}

export function filterPorts(
  sockets: SocketEntry[],
  query: string,
  contextPaths: Map<string, string>,
  portsFilter: 'listeners' | 'all',
  protocol: 'all' | 'tcp' | 'udp',
  connectionState: 'all' | SocketState,
  portScope: ProcessKey | null,
): SocketEntry[] {
  return sockets
    .filter((entry) => {
      if (portsFilter === 'listeners' && !listenerPortFilter(entry)) return false
      if (protocol !== 'all' && entry.protocol !== protocol) return false
      if (connectionState !== 'all' && entry.state !== connectionState) return false
      if (portScope && (!entry.processKey || processKeyId(entry.processKey) !== processKeyId(portScope))) {
        return false
      }
      return matchesPortSearch(entry, query, contextPaths)
    })
    .sort((a, b) => a.localPort - b.localPort || a.localAddress.localeCompare(b.localAddress))
}
