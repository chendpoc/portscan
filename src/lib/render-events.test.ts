import { describe, expect, it } from 'vitest'
import {
  applyBootstrapMonitorState,
  applyProcessError,
  applyProcessSnapshot,
  monitorCycleGeneration,
  reduceProcessErrorEvent,
  reduceRefreshComplete,
  reduceRefreshFatal,
  shouldClearFatalError,
} from './render-events'

describe('render-events', () => {
  it('rejects older process snapshots after a newer generation was seen', () => {
    const state = { processSeen: 5, socketSeen: 0 }
    const older = applyProcessSnapshot(state, {
      generation: 4,
      capturedAt: new Date().toISOString(),
      entries: [],
    })
    expect(older.accepted).toBe(false)
    expect(older.state.processSeen).toBe(5)
  })

  it('accepts newer snapshots and advances seen generation', () => {
    const applied = applyProcessSnapshot(
      { processSeen: 2, socketSeen: 0 },
      { generation: 3, capturedAt: new Date().toISOString(), entries: [] },
    )
    expect(applied.accepted).toBe(true)
    expect(applied.state.processSeen).toBe(3)
  })

  it('records process errors at their generation without rewinding', () => {
    const next = applyProcessError({ processSeen: 4, socketSeen: 0 }, { generation: 5, message: 'fail' })
    expect(next.processSeen).toBe(5)
    const stale = applyProcessError(next, { generation: 3, message: 'old' })
    expect(stale.processSeen).toBe(5)
  })

  it('does not apply stale process error messages after a newer generation was seen', () => {
    const reduced = reduceProcessErrorEvent({ processSeen: 6, socketSeen: 0 }, { generation: 4, message: 'old' })
    expect(reduced.message).toBeNull()
    expect(reduced.state.processSeen).toBe(6)
  })

  it('bootstrap does not rewind processSeen when initial snapshot is older than live events', () => {
    const merged = applyBootstrapMonitorState(
      { processSeen: 8, socketSeen: 3 },
      { processes: null, sockets: null, processError: null, socketError: null },
      {
        processes: { generation: 5, capturedAt: new Date().toISOString(), entries: [] },
        sockets: null,
        processError: 'stale failure',
        processErrorGeneration: 5,
        socketError: null,
      },
    )
    expect(merged.state.processSeen).toBe(8)
    expect(merged.monitor.processes).toBeNull()
    expect(merged.monitor.processError).toBeNull()
  })

  it('only clears fatal errors after a matching or newer refresh completion', () => {
    expect(shouldClearFatalError(5, 4)).toBe(false)
    expect(shouldClearFatalError(5, 5)).toBe(true)
    expect(shouldClearFatalError(5, 6)).toBe(true)
  })

  it('ignores duplicate and stale refresh-complete generations', () => {
    expect(reduceRefreshComplete(5, 5, 5).accepted).toBe(false)
    expect(reduceRefreshComplete(5, 4, 5).accepted).toBe(false)
    const newer = reduceRefreshComplete(5, 6, 6)
    expect(newer.accepted).toBe(true)
    expect(newer.cycleSeen).toBe(6)
  })

  it('rejects delayed refresh-fatal payloads after a newer cycle was seen', () => {
    const stale = reduceRefreshFatal(8, { generation: 6, message: 'late fatal' }, 8)
    expect(stale.accepted).toBe(false)
    expect(stale.message).toBeNull()
    const fresh = reduceRefreshFatal(3, { generation: 4, message: 'current fatal' }, 3)
    expect(fresh.accepted).toBe(true)
    expect(fresh.message).toBe('current fatal')
  })

  it('rejects completion and fatal older than either source without rejecting the matching completion', () => {
    expect(reduceRefreshComplete(2, 9, 10).accepted).toBe(false)
    expect(reduceRefreshFatal(2, { generation: 9, message: 'late' }, 10).accepted).toBe(false)
    const matching = reduceRefreshComplete(2, 10, 10)
    expect(matching.accepted).toBe(true)
    expect(reduceRefreshComplete(matching.cycleSeen, 10, 10).accepted).toBe(false)
  })

  it('derives bootstrap cycle generation from snapshots and source errors', () => {
    const generation = monitorCycleGeneration({
      processes: { generation: 4, capturedAt: new Date().toISOString(), entries: [] },
      sockets: null,
      processError: 'fail',
      socketError: null,
      processErrorGeneration: 6,
      socketErrorGeneration: null,
    })
    expect(generation).toBe(6)
  })
})
