import { describe, expect, it } from 'vitest'
import { createDetailController } from './inspector-detail'
import type { ProcessDetail, ProcessKey } from './types'

const key = (pid: number): ProcessKey => ({ pid, startSec: 100, startUsec: 1 })

const detailFor = (pid: number): ProcessDetail => ({
  key: key(pid),
  command: ['test', String(pid)],
  exe: '/bin/test',
  cwd: { state: 'available', path: '/tmp', message: null },
  executable: { state: 'available', path: '/bin/test', message: null },
  appBundle: null,
  collectedAt: new Date().toISOString(),
  verifiedAt: new Date().toISOString(),
  ancestry: [],
  ancestryIncomplete: false,
  startTimeIso: null,
})

describe('inspector detail controller', () => {
  it('keeps at most one in-flight detail fetch and applies the latest selection', async () => {
    let inFlight = 0
    let maxInFlight = 0
    const controller = createDetailController(async (selected) => {
      inFlight += 1
      maxInFlight = Math.max(maxInFlight, inFlight)
      await new Promise((resolve) => setTimeout(resolve, 20))
      inFlight -= 1
      return detailFor(selected.pid)
    })

    controller.select(key(1))
    controller.select(key(2))
    await new Promise((resolve) => setTimeout(resolve, 150))
    expect(maxInFlight).toBe(1)
    expect(controller.state.detail?.key.pid).toBe(2)
  })

  it('deduplicates detail refresh for the same cycle generation', async () => {
    let calls = 0
    const controller = createDetailController(async (selected) => {
      calls += 1
      return detailFor(selected.pid)
    })
    controller.select(key(9))
    await new Promise((resolve) => setTimeout(resolve, 10))
    controller.noteCycle(4)
    controller.noteCycle(4)
    await new Promise((resolve) => setTimeout(resolve, 30))
    expect(calls).toBe(2)
  })

  it('refreshes on every cycle notification while selected', async () => {
    let calls = 0
    const controller = createDetailController(async (selected) => {
      calls += 1
      return detailFor(selected.pid)
    })
    controller.select(key(9))
    await new Promise((resolve) => setTimeout(resolve, 10))
    controller.noteCycle(1)
    controller.noteCycle(1)
    controller.noteCycle(2)
    await new Promise((resolve) => setTimeout(resolve, 30))
    expect(calls).toBe(3)
  })

  it('does not tight-loop after a failed fetch', async () => {
    let calls = 0
    const controller = createDetailController(async () => {
      calls += 1
      throw new Error('denied')
    })
    controller.select(key(3))
    await new Promise((resolve) => setTimeout(resolve, 40))
    expect(calls).toBe(1)
    expect(controller.state.detailError).toContain('denied')
    expect(controller.state.detailLoading).toBe(false)
  })

  it('ignores late replies after rapid A→B→A selection', async () => {
    const delays = new Map<number, number>([[1, 40], [2, 5], [1, 5]])
    const controller = createDetailController(async (selected) => {
      await new Promise((resolve) => setTimeout(resolve, delays.get(selected.pid) ?? 0))
      return detailFor(selected.pid)
    })
    controller.select(key(1))
    controller.select(key(2))
    controller.select(key(1))
    await new Promise((resolve) => setTimeout(resolve, 80))
    expect(controller.state.detail?.command?.[1]).toBe('1')
  })

  it('drops stale replies after close', async () => {
    let resolveFetch: (() => void) | undefined
    const controller = createDetailController(async () => {
      await new Promise<void>((resolve) => {
        resolveFetch = resolve
      })
      return detailFor(1)
    })
    controller.select(key(1))
    controller.close()
    resolveFetch?.()
    await new Promise((resolve) => setTimeout(resolve, 10))
    expect(controller.state.selectedKey).toBeNull()
    expect(controller.state.detail).toBeNull()
  })

  it('notifies subscribers when async detail completes', async () => {
    let revisions = 0
    const controller = createDetailController(async (selected) => detailFor(selected.pid), () => {
      revisions += 1
    })
    controller.select(key(4))
    await new Promise((resolve) => setTimeout(resolve, 10))
    expect(revisions).toBeGreaterThan(1)
    expect(controller.state.detail?.key.pid).toBe(4)
  })
})
