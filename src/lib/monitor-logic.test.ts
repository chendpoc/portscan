import { describe, expect, it } from 'vitest'
import { processKeyId } from './format'
import {
  compareProcess,
  filterProcesses,
  isSnapshotStale,
  listenerPortFilter,
  listenPortsByProcess,
  matchesProcessSearch,
  parseNumericQuery,
  staleThresholdMs,
} from './monitor-logic'
import type { ProcessEntry, SocketEntry } from './types'

const key = (pid: number) => ({ pid, startSec: 10, startUsec: 1 })

const entry = (overrides: Partial<ProcessEntry> = {}): ProcessEntry => ({
  key: key(1),
  name: 'node',
  cpuPercent: 1,
  rssBytes: 100,
  status: 'running',
  parentPid: 1,
  cwd: { state: 'available', path: '/Users/dev/project', message: null },
  executable: { state: 'available', path: '/usr/local/bin/node', message: null },
  contextDisplay: '~/project',
  contextKind: 'cwd',
  ...overrides,
})

describe('monitor-logic', () => {
  it('uses max(3x interval, 5000ms) stale threshold', () => {
    expect(staleThresholdMs(1000)).toBe(5000)
    expect(staleThresholdMs(2000)).toBe(6000)
  })

  it('marks failed sources stale immediately and ages with clock', () => {
    const now = Date.now()
    expect(isSnapshotStale(new Date(now - 7000).toISOString(), 2000, false, now)).toBe(true)
    expect(isSnapshotStale(new Date(now - 1000).toISOString(), 2000, false, now)).toBe(false)
    expect(isSnapshotStale(new Date().toISOString(), 2000, true, now)).toBe(true)
  })

  it('matches numeric port only for the owning process', () => {
    const owner = entry({ key: key(8787) })
    const other = entry({ key: key(2), name: 'python3' })
    const portSets = listenPortsByProcess([
      {
        pid: 8787,
        processName: 'node',
        processKey: key(8787),
        protocol: 'tcp',
        state: 'listen',
        localAddress: '127.0.0.1',
        localPort: 8787,
        remoteAddress: null,
        remotePort: null,
      },
    ])
    expect(matchesProcessSearch(owner, '8787', portSets.get(processKeyId(key(8787))) ?? [])).toBe(true)
    expect(matchesProcessSearch(other, '8787', portSets.get(processKeyId(key(2))) ?? [])).toBe(false)
  })

  it('filters processes through per-entry port ownership', () => {
    const portSets = listenPortsByProcess([
      {
        pid: 8787,
        processName: 'node',
        processKey: key(8787),
        protocol: 'tcp',
        state: 'listen',
        localAddress: '127.0.0.1',
        localPort: 8787,
        remoteAddress: null,
        remotePort: null,
      },
    ] as SocketEntry[])
    const filtered = filterProcesses(
      [entry({ key: key(8787) }), entry({ key: key(99), name: 'redis' })],
      '8787',
      portSets,
      'all',
      'cpu',
      true,
    )
    expect(filtered).toHaveLength(1)
    expect(filtered[0]?.key.pid).toBe(8787)
  })

  it('sorts unknown cpu values last with deterministic pid tie-break', () => {
    const left = entry({ key: key(2), cpuPercent: null })
    const right = entry({ key: key(1), cpuPercent: 3 })
    expect(compareProcess(left, right, 'cpu', true)).toBeGreaterThan(0)
  })

  it('filters listener and bound udp endpoints', () => {
    const listen: SocketEntry = {
      pid: 1,
      processName: 'node',
      processKey: key(1),
      protocol: 'tcp',
      state: 'listen',
      localAddress: '127.0.0.1',
      localPort: 3000,
      remoteAddress: null,
      remotePort: null,
    }
    expect(listenerPortFilter(listen)).toBe(true)
    expect(listenerPortFilter({ ...listen, protocol: 'udp', state: 'none' })).toBe(true)
    expect(listenerPortFilter({ ...listen, state: 'established' })).toBe(false)
  })

  it('filters one thousand processes within 100ms', () => {
    const entries = Array.from({ length: 1000 }, (_, index) =>
      entry({ key: key(index + 1), name: `proc-${index}`, cpuPercent: index % 100 }),
    )
    const portSets = new Map<string, Set<number>>()
    const start = performance.now()
    filterProcesses(entries, 'proc-9', portSets, 'all', 'cpu', true)
    expect(performance.now() - start).toBeLessThan(100)
  })

  it('parses numeric queries safely', () => {
    expect(parseNumericQuery('8787')).toBe(8787)
    expect(parseNumericQuery('12a')).toBeNull()
  })
})
