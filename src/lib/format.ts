import type { SocketEntry, SocketSnapshot, SocketState } from './types'

const STATE_LABEL: Record<SocketState, string> = {
  closed: '已关闭',
  listen: '监听',
  syn_sent: 'SYN_SENT',
  syn_received: 'SYN_RECV',
  established: '已连接',
  fin_wait1: 'FIN_WAIT1',
  fin_wait2: 'FIN_WAIT2',
  close_wait: 'CLOSE_WAIT',
  closing: 'CLOSING',
  last_ack: 'LAST_ACK',
  time_wait: 'TIME_WAIT',
  delete_tcb: 'DELETE_TCB',
  unknown: '未知',
  none: '—',
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

export function formatBytes(value: number): string {
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

export function formatTime(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return date.toLocaleTimeString('zh-CN', { hour12: false })
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

export function fixtureSnapshot(): SocketSnapshot {
  return {
    capturedAt: new Date().toISOString(),
    interfaces: [
      { name: 'en0', receivedBytes: 842112000, transmittedBytes: 120334000 },
      { name: 'lo0', receivedBytes: 4096, transmittedBytes: 4096 },
    ],
    sockets: [
      {
        pid: 412,
        processName: 'node',
        protocol: 'tcp',
        state: 'listen',
        localAddress: '127.0.0.1',
        localPort: 1420,
        remoteAddress: null,
        remotePort: null,
      },
      {
        pid: 88,
        processName: 'rapportd',
        protocol: 'tcp',
        state: 'listen',
        localAddress: '0.0.0.0',
        localPort: 49152,
        remoteAddress: null,
        remotePort: null,
      },
      {
        pid: 1204,
        processName: 'Cursor',
        protocol: 'tcp',
        state: 'established',
        localAddress: '192.168.1.20',
        localPort: 52311,
        remoteAddress: '93.184.216.34',
        remotePort: 443,
      },
      {
        pid: 331,
        processName: 'mDNSResponder',
        protocol: 'udp',
        state: 'none',
        localAddress: '0.0.0.0',
        localPort: 5353,
        remoteAddress: null,
        remotePort: null,
      },
    ],
  }
}
