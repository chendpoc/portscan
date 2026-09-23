export type Protocol = 'tcp' | 'udp'

export type SocketState =
  | 'closed'
  | 'listen'
  | 'syn_sent'
  | 'syn_received'
  | 'established'
  | 'fin_wait1'
  | 'fin_wait2'
  | 'close_wait'
  | 'closing'
  | 'last_ack'
  | 'time_wait'
  | 'delete_tcb'
  | 'unknown'
  | 'none'

export type SocketEntry = {
  pid: number | null
  processName: string | null
  protocol: Protocol
  state: SocketState
  localAddress: string
  localPort: number
  remoteAddress: string | null
  remotePort: number | null
}

export type InterfaceInfo = {
  name: string
  receivedBytes: number
  transmittedBytes: number
}

export type SocketSnapshot = {
  capturedAt: string
  sockets: SocketEntry[]
  interfaces: InterfaceInfo[]
}

export type RefreshSettings = {
  intervalMs: number
  paused: boolean
  includeUdp: boolean
  includeIpv6: boolean
}

export type LsofSample = {
  lineCount: number
}

export type RenderStatus = 'loading' | 'live' | 'paused' | 'error'
