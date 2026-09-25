import {
  formatBytes,
  formatCommand,
  formatCpuPercent,
  formatEndpoint,
  pathEvidenceLabel,
  processKeyId,
  stateLabel,
} from './format'
import type { PathEvidence, ProcessDetail, ProcessEntry, ProcessKey, SocketEntry } from './types'

export function buildInspectorReport(options: {
  process: ProcessEntry | undefined
  detail: ProcessDetail | null
  key: ProcessKey
  exited: boolean
  endpoints: SocketEntry[]
  processCapturedAt?: string | null
  endpointsCapturedAt?: string | null
  processStale?: boolean
  socketStale?: boolean
  detailStale?: boolean
  processError?: string | null
  socketError?: string | null
  detailError?: string | null
}): string {
  const {
    process,
    detail,
    key,
    exited,
    endpoints,
    processCapturedAt,
    endpointsCapturedAt,
    processStale,
    socketStale,
    detailStale,
    processError,
    socketError,
    detailError,
  } = options
  const lines: string[] = []
  lines.push(`Process: ${process?.name ?? 'Unknown'}`)
  lines.push(`Identity: ${processKeyId(key)}`)
  lines.push(`PID: ${key.pid}`)
  if (exited) {
    lines.push('State: Process exited or changed (historical evidence below)')
  } else if (process) {
    lines.push(`CPU: ${formatCpuPercent(process.cpuPercent)}`)
    lines.push(`RSS: ${formatBytes(process.rssBytes)}`)
  } else {
    lines.push('CPU: Unavailable')
    lines.push('RSS: Unavailable')
  }
  if (exited && process) {
    lines.push(`Historical CPU: ${formatCpuPercent(process.cpuPercent)}`)
    lines.push(`Historical RSS: ${formatBytes(process.rssBytes)}`)
  }
  const cwd: PathEvidence | undefined = detail?.cwd ?? process?.cwd
  const executable: PathEvidence | undefined = detail?.executable ?? process?.executable
  lines.push(`CWD: ${pathEvidenceLabel(cwd ?? { state: 'unavailable', path: null, message: null })}`)
  lines.push(`Executable: ${pathEvidenceLabel(executable ?? { state: 'unavailable', path: null, message: null })}`)
  if (detail?.appBundle) lines.push(`App bundle: ${detail.appBundle}`)
  if (detail?.command?.length) {
    lines.push(`Command (shell): ${formatCommand(detail.command)}`)
    lines.push(`Command (argv JSON): ${JSON.stringify(detail.command)}`)
  } else if (detailError) {
    lines.push(`Command: Unavailable (${detailError})`)
  } else {
    lines.push('Command: Unavailable from macOS')
  }
  if (detail?.startTimeIso) {
    lines.push(`Process start: ${detail.startTimeIso}`)
  } else {
    lines.push('Process start: Unavailable')
  }
  if (detail?.ancestry.length) {
    lines.push('Ancestry:')
    for (const node of detail.ancestry) {
      lines.push(`  - ${node.name} (${processKeyId(node.key)})${node.relationshipVerified ? '' : ' [unverified]'}`)
    }
    if (detail.ancestryIncomplete) lines.push('  (ancestry incomplete)')
  } else if (detail) {
    lines.push('Ancestry: (empty or unavailable)')
    if (detail.ancestryIncomplete) lines.push('  (ancestry incomplete)')
  } else {
    lines.push('Ancestry: Unavailable')
  }
  lines.push('Endpoints:')
  if (endpoints.length) {
    for (const entry of endpoints) {
      const local = formatEndpoint(entry.localAddress, entry.localPort)
      const remote = entry.remoteAddress
        ? ` -> ${formatEndpoint(entry.remoteAddress, entry.remotePort)}`
        : ''
      lines.push(
        `  - ${entry.protocol.toUpperCase()} ${local}${remote} ${stateLabel(entry.state)}`,
      )
    }
    if (endpointsCapturedAt) {
      lines.push(`  Endpoints captured: ${endpointsCapturedAt}${socketStale ? ' [stale]' : ''}`)
    }
  } else {
    lines.push('  (none observed for this process instance)')
  }
  if (processCapturedAt) {
    lines.push(`Process snapshot: ${processCapturedAt}${processStale ? ' [stale]' : ''}`)
  } else {
    lines.push('Process snapshot: Unavailable')
  }
  if (processError) lines.push(`Process source error: ${processError}`)
  if (endpointsCapturedAt) {
    lines.push(`Socket snapshot: ${endpointsCapturedAt}${socketStale ? ' [stale]' : ''}`)
  } else if (endpoints.length === 0) {
    lines.push('Socket snapshot: Unavailable')
  }
  if (socketError) lines.push(`Socket source error: ${socketError}`)
  if (detail?.collectedAt) {
    lines.push(`Detail collected: ${detail.collectedAt}${detailStale ? ' [stale]' : ''}`)
  } else {
    lines.push('Detail collected: Unavailable')
  }
  if (detail?.verifiedAt) {
    lines.push(`Detail verified: ${detail.verifiedAt}${detailStale ? ' [stale]' : ''}`)
  } else if (!detailError) {
    lines.push('Detail verified: Unavailable')
  }
  if (detailError) lines.push(`Detail error: ${detailError}`)
  return lines.join('\n')
}
