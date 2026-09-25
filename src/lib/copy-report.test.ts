import { describe, expect, it } from 'vitest'
import { buildInspectorReport } from './copy-report'
import type { ProcessKey } from './types'

const key: ProcessKey = { pid: 42, startSec: 100, startUsec: 1 }

describe('buildInspectorReport', () => {
  it('uses ISO timestamps and historical endpoint capture time', () => {
    const processCaptured = '2026-09-24T08:00:00.000Z'
    const endpointsCaptured = '2026-09-24T08:00:01.000Z'
    const report = buildInspectorReport({
      key,
      exited: true,
      endpoints: [
        {
          pid: 42,
          processName: 'node',
          processKey: key,
          protocol: 'tcp',
          state: 'listen',
          localAddress: '127.0.0.1',
          localPort: 8787,
          remoteAddress: null,
          remotePort: null,
        },
      ],
      process: {
        key,
        name: 'node',
        cpuPercent: 1,
        rssBytes: 1024,
        status: 'running',
        parentPid: 1,
        cwd: { state: 'available', path: '/tmp/a', message: null },
        executable: { state: 'available', path: '/bin/node', message: null },
        contextDisplay: '/tmp/a',
        contextKind: 'cwd',
      },
      detail: {
        key,
        command: ['node', 'file with space'],
        exe: '/bin/node',
        cwd: { state: 'available', path: '/tmp/a', message: null },
        executable: { state: 'available', path: '/bin/node', message: null },
        appBundle: null,
        collectedAt: '2026-09-24T08:00:02.000Z',
        verifiedAt: '2026-09-24T08:00:03.000Z',
        ancestry: [],
        ancestryIncomplete: true,
        startTimeIso: '2026-09-24T07:00:00.000Z',
      },
      processCapturedAt: processCaptured,
      endpointsCapturedAt: endpointsCaptured,
      processError: 'process source failed',
      socketError: 'socket source failed',
    })
    expect(report).toContain(`Process snapshot: ${processCaptured}`)
    expect(report).toContain(`Socket snapshot: ${endpointsCaptured}`)
    expect(report).toContain('Endpoints captured: 2026-09-24T08:00:01.000Z')
    expect(report).toContain("Command (shell): node 'file with space'")
    expect(report).toContain('Command (argv JSON): ["node","file with space"]')
    expect(report).toContain('Process source error: process source failed')
    expect(report).toContain('Socket source error: socket source failed')
    expect(report).toContain('(ancestry incomplete)')
  })

  it('includes remote endpoints and explicit missing sources', () => {
    const report = buildInspectorReport({
      key,
      exited: false,
      endpoints: [
        {
          pid: 42,
          processName: 'node',
          processKey: key,
          protocol: 'tcp',
          state: 'established',
          localAddress: '127.0.0.1',
          localPort: 5000,
          remoteAddress: '93.184.216.34',
          remotePort: 443,
        },
      ],
      process: undefined,
      detail: null,
      detailError: 'denied',
      socketError: 'socket down',
    })
    expect(report).toContain('-> 93.184.216.34:443')
    expect(report).toContain('Process snapshot: Unavailable')
    expect(report).toContain('Socket source error: socket down')
    expect(report).toContain('Detail error: denied')
  })
})
