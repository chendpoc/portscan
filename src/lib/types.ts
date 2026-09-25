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

export type EvidenceState = 'available' | 'restricted' | 'unavailable'

export type PathEvidence = {
  state: EvidenceState
  path: string | null
  message: string | null
}

export type SocketEntry = {
  pid: number | null
  processName: string | null
  processKey: ProcessKey | null
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

export type ProcessKey = {
  pid: number
  startSec: number
  startUsec: number | null
}

export type ProcessState = 'running' | 'sleeping' | 'stopped' | 'zombie' | 'unknown'

export type ProcessEntry = {
  key: ProcessKey
  name: string
  cpuPercent: number | null
  rssBytes: number | null
  status: ProcessState
  parentPid: number | null
  cwd: PathEvidence
  executable: PathEvidence
  contextDisplay: string | null
  contextKind: string | null
}

export type AncestryNode = {
  key: ProcessKey
  name: string
  relationshipVerified: boolean
}

export type ProcessDetail = {
  key: ProcessKey
  command: string[] | null
  exe: string | null
  cwd: PathEvidence
  executable: PathEvidence
  appBundle: string | null
  collectedAt: string
  verifiedAt: string
  ancestry: AncestryNode[]
  ancestryIncomplete: boolean
  startTimeIso: string | null
}

export type ProcessSnapshot = {
  generation: number
  capturedAt: string
  entries: ProcessEntry[]
}

export type SocketSnapshot = {
  generation: number
  capturedAt: string
  sockets: SocketEntry[]
  interfaces: InterfaceInfo[]
}

export type MonitorState = {
  processes: ProcessSnapshot | null
  sockets: SocketSnapshot | null
  processError: string | null
  socketError: string | null
  processErrorGeneration?: number | null
  socketErrorGeneration?: number | null
}

export type SnapshotError = {
  generation: number
  message: string
}

export type RefreshFatal = {
  generation: number
  message: string
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

export type RenderStatus = 'loading' | 'live' | 'paused' | 'error' | 'stale'

export type PrimaryView = 'processes' | 'ports'

export type PortsFilter = 'listeners' | 'all'
