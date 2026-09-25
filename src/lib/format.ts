import type { MonitorState, PathEvidence, ProcessKey, ProcessState, SocketEntry, SocketState } from './types'

const available = (path: string): PathEvidence => ({ state: 'available', path, message: null })
const unavailable = (message: string): PathEvidence => ({ state: 'unavailable', path: null, message })

export function pathEvidenceLabel(evidence: PathEvidence): string {
  if (evidence.state === 'available' && evidence.path) return evidence.path
  if (evidence.state === 'restricted') return evidence.message ?? 'Restricted by macOS'
  return evidence.message ?? 'Unavailable from macOS'
}

const STATE_LABEL: Record<SocketState, string> = {
  closed: 'CLOSED',
  listen: 'LISTEN',
  syn_sent: 'SYN_SENT',
  syn_received: 'SYN_RECV',
  established: 'ESTABLISHED',
  fin_wait1: 'FIN_WAIT1',
  fin_wait2: 'FIN_WAIT2',
  close_wait: 'CLOSE_WAIT',
  closing: 'CLOSING',
  last_ack: 'LAST_ACK',
  time_wait: 'TIME_WAIT',
  delete_tcb: 'DELETE_TCB',
  unknown: 'UNKNOWN',
  none: 'BOUND',
}

const PROCESS_STATE_LABEL: Record<ProcessState, string> = {
  running: 'Running', sleeping: 'Sleeping', stopped: 'Stopped', zombie: 'Zombie', unknown: 'Unknown',
}

export function processStateLabel(state: ProcessState): string {
  return PROCESS_STATE_LABEL[state]
}

export function processKeyId(key: ProcessKey): string {
  return `${key.pid}:${key.startSec}:${key.startUsec ?? 'unknown'}`
}

export function stateLabel(state: SocketState): string {
  return STATE_LABEL[state]
}

export function stateClass(state: SocketState): string {
  if (state === 'listen') return 'listen'
  if (state === 'established') return 'established'
  if (state === 'none') return 'none'
  return 'other'
}

export function formatEndpoint(address: string | null, port: number | null): string {
  if (!address || port == null) return '—'
  const host = address.includes(':') ? `[${address}]` : address
  return `${host}:${port}`
}

export function formatBytes(value: number | null): string {
  if (value == null) return 'Unavailable'
  if (value < 1024) return `${value} B`
  const units = ['KB', 'MB', 'GB', 'TB']
  let size = value / 1024
  let unit = 0
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024
    unit += 1
  }
  const digits = size >= 100 ? 0 : 1
  return `${size.toFixed(digits)} ${units[unit]}`
}

export function formatCpuPercent(value: number | null): string {
  return value == null ? 'Sampling…' : `${value.toFixed(1)}%`
}

export function formatCommand(args: string[]): string {
  return args
    .map((arg) => /^[a-zA-Z0-9_./:@%+=,-]+$/.test(arg) ? arg : `'${arg.replaceAll("'", "'\\''")}'`)
    .join(' ')
}

export function formatTime(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return date.toLocaleTimeString('en-US', { hour12: false })
}

export function formatUptime(startSec: number, nowMs: number): string {
  const elapsed = Math.max(0, Math.floor(nowMs / 1000) - startSec)
  const hours = Math.floor(elapsed / 3600)
  const minutes = Math.floor((elapsed % 3600) / 60)
  const seconds = elapsed % 60
  if (hours > 0) return `${hours}h ${minutes}m`
  if (minutes > 0) return `${minutes}m ${seconds}s`
  return `${seconds}s`
}

export function formatRelativeAge(iso: string | null | undefined, nowMs: number): string {
  if (!iso) return '—'
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return '—'
  const seconds = Math.max(0, Math.floor((nowMs - date.getTime()) / 1000))
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  return `${hours}h ago`
}

export function rowKey(entry: SocketEntry, index: number): string {
  return [
    index,
    entry.pid ?? 'none',
    entry.protocol,
    entry.localAddress,
    entry.localPort,
    entry.remoteAddress ?? '',
    entry.remotePort ?? '',
    entry.state,
  ].join('|')
}

export function fixtureMonitorState(): MonitorState {
  const capturedAt = new Date().toISOString()
  const nowSec = Math.floor(Date.now() / 1000)
  const nodeApiStart = nowSec - 8280
  const key = (pid: number, startSec: number, startUsec: number): ProcessKey => ({ pid, startSec, startUsec })
  const nodeApi = key(48291, nodeApiStart, 482910)
  const nodeWeb = key(39018, nowSec - 5400, 390180)
  const ollama = key(9122, nowSec - 36000, 91220)
  const python = key(8080, nowSec - 7200, 80800)
  const postgres = key(5432, nowSec - 86400, 54320)
  const redis = key(6379, nowSec - 86400, 63790)
  const cursor = key(1204, nowSec - 1800, 12040)
  const windowServer = key(715, nowSec - 86400, 7150)
  const entries = [
    { key: ollama, name: 'ollama', cpuPercent: 38.4, rssBytes: 8804682956, status: 'running' as const, parentPid: 1,
      cwd: available('/Applications/Ollama.app'), executable: available('/Applications/Ollama.app/Contents/MacOS/Ollama'),
      contextDisplay: '/Applications/Ollama.app', contextKind: 'cwd' },
    { key: nodeApi, name: 'node', cpuPercent: 18.2, rssBytes: 404750336, status: 'running' as const, parentPid: 9001,
      cwd: available('/Users/dev/code/api-red'), executable: available('/usr/local/bin/node'),
      contextDisplay: '~/code/api-red', contextKind: 'cwd' },
    { key: python, name: 'python3', cpuPercent: 6.1, rssBytes: 819986432, status: 'running' as const, parentPid: 1,
      cwd: available('/Users/dev/work/ml-service'), executable: available('/usr/local/bin/python3'),
      contextDisplay: '~/work/ml-service', contextKind: 'cwd' },
    { key: nodeWeb, name: 'node', cpuPercent: 2.1, rssBytes: 222298112, status: 'running' as const, parentPid: 1,
      cwd: available('/Users/dev/code/web-ui'), executable: available('/usr/local/bin/node'),
      contextDisplay: '~/code/web-ui', contextKind: 'cwd' },
    { key: postgres, name: 'postgres', cpuPercent: 0.7, rssBytes: 643825664, status: 'running' as const, parentPid: 1,
      cwd: available('/usr/local/var/postgres'), executable: available('/usr/local/bin/postgres'),
      contextDisplay: '/usr/local/var/postgres', contextKind: 'cwd' },
    { key: redis, name: 'redis-server', cpuPercent: 0.2, rssBytes: 44040192, status: 'running' as const, parentPid: 1,
      cwd: available('/usr/local/var/redis'), executable: available('/usr/local/bin/redis-server'),
      contextDisplay: '/usr/local/var/redis', contextKind: 'cwd' },
    { key: cursor, name: 'Cursor', cpuPercent: 0.1, rssBytes: 1503238553, status: 'running' as const, parentPid: 1,
      cwd: available('/Users/dev/code/web-ui'), executable: available('/Applications/Cursor.app/Contents/MacOS/Cursor'),
      contextDisplay: '~/code/web-ui', contextKind: 'cwd' },
    { key: windowServer, name: 'WindowServer', cpuPercent: 0.1, rssBytes: 536870912, status: 'running' as const, parentPid: 1,
      cwd: unavailable('Unavailable from macOS'), executable: unavailable('Unavailable from macOS'),
      contextDisplay: 'Unavailable from macOS', contextKind: 'unavailable' },
  ]
  return {
    processError: null,
    socketError: null,
    processErrorGeneration: null,
    socketErrorGeneration: null,
    processes: { generation: 1, capturedAt, entries },
    sockets: {
      generation: 1,
      capturedAt,
      interfaces: [
        { name: 'en0', receivedBytes: 842112000, transmittedBytes: 120334000 },
        { name: 'lo0', receivedBytes: 4096, transmittedBytes: 4096 },
      ],
      sockets: [
        { pid: 9122, processName: 'ollama', processKey: ollama, protocol: 'tcp', state: 'listen', localAddress: '127.0.0.1', localPort: 11434, remoteAddress: null, remotePort: null },
        { pid: 48291, processName: 'node', processKey: nodeApi, protocol: 'tcp', state: 'listen', localAddress: '127.0.0.1', localPort: 8787, remoteAddress: null, remotePort: null },
        { pid: 48291, processName: 'node', processKey: nodeApi, protocol: 'tcp', state: 'listen', localAddress: '::1', localPort: 8787, remoteAddress: null, remotePort: null },
        { pid: 8080, processName: 'python3', processKey: python, protocol: 'tcp', state: 'listen', localAddress: '127.0.0.1', localPort: 8080, remoteAddress: null, remotePort: null },
        { pid: 39018, processName: 'node', processKey: nodeWeb, protocol: 'tcp', state: 'listen', localAddress: '127.0.0.1', localPort: 3000, remoteAddress: null, remotePort: null },
        { pid: 5432, processName: 'postgres', processKey: postgres, protocol: 'tcp', state: 'listen', localAddress: '127.0.0.1', localPort: 5432, remoteAddress: null, remotePort: null },
        { pid: 6379, processName: 'redis-server', processKey: redis, protocol: 'tcp', state: 'listen', localAddress: '127.0.0.1', localPort: 6379, remoteAddress: null, remotePort: null },
        { pid: 1204, processName: 'Cursor', processKey: cursor, protocol: 'tcp', state: 'established', localAddress: '192.168.1.20', localPort: 52311, remoteAddress: '93.184.216.34', remotePort: 443 },
        { pid: 1204, processName: 'Cursor', processKey: cursor, protocol: 'tcp', state: 'established', localAddress: '::1', localPort: 52312, remoteAddress: '2001:db8::1', remotePort: 443 },
        { pid: 6379, processName: 'redis-server', processKey: redis, protocol: 'udp', state: 'none', localAddress: '0.0.0.0', localPort: 6379, remoteAddress: null, remotePort: null },
      ],
    },
  }
}
