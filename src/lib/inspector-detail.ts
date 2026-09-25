import type { ProcessDetail, ProcessKey } from './types'
import { processKeyId } from './format'

export type DetailFetch = (key: ProcessKey) => Promise<ProcessDetail>

export type DetailControllerState = {
  selectedKey: ProcessKey | null
  detail: ProcessDetail | null
  detailError: string | null
  detailLoading: boolean
  detailCapturedAt: string | null
  requestToken: number
  inflight: boolean
  pendingRefresh: boolean
  lastCycleNotified: number
}

export type DetailNotify = () => void

export function createDetailController(fetchDetail: DetailFetch, notify: DetailNotify = () => {}) {
  const state: DetailControllerState = {
    selectedKey: null,
    detail: null,
    detailError: null,
    detailLoading: false,
    detailCapturedAt: null,
    requestToken: 0,
    inflight: false,
    pendingRefresh: false,
    lastCycleNotified: -1,
  }

  function touch() {
    notify()
  }

  async function pump() {
    if (state.inflight || !state.selectedKey || !state.pendingRefresh) return
    state.inflight = true
    touch()
    try {
      while (state.selectedKey && state.pendingRefresh) {
        state.pendingRefresh = false
        touch()
        const key = state.selectedKey
        const token = ++state.requestToken
        state.detailLoading = true
        state.detailError = null
        touch()
        try {
          const next = await fetchDetail(key)
          if (token !== state.requestToken || !keysEqual(state.selectedKey, key)) continue
          state.detail = next
          state.detailCapturedAt = next.verifiedAt
        } catch (cause) {
          if (token !== state.requestToken || !keysEqual(state.selectedKey, key)) continue
          state.detailError = String(cause)
        } finally {
          if (token === state.requestToken) state.detailLoading = false
          touch()
        }
      }
    } finally {
      state.inflight = false
      touch()
      if (state.pendingRefresh && state.selectedKey) void pump()
    }
  }

  return {
    get state() {
      return state
    },
    select(key: ProcessKey | null) {
      if (key && state.selectedKey && keysEqual(state.selectedKey, key)) {
        return
      }
      state.selectedKey = key
      state.detail = null
      state.detailError = null
      state.detailCapturedAt = null
      state.lastCycleNotified = -1
      state.requestToken += 1
      state.pendingRefresh = Boolean(key)
      touch()
      if (key) void pump()
    },
    close() {
      state.selectedKey = null
      state.detail = null
      state.detailError = null
      state.detailCapturedAt = null
      state.detailLoading = false
      state.pendingRefresh = false
      state.lastCycleNotified = -1
      state.requestToken += 1
      touch()
    },
    noteCycle(cycleGeneration: number) {
      if (!state.selectedKey) return
      if (cycleGeneration <= state.lastCycleNotified) return
      state.lastCycleNotified = cycleGeneration
      state.pendingRefresh = true
      touch()
      void pump()
    },
    maxConcurrentInvokes() {
      return state.inflight ? 1 : 0
    },
  }
}

function keysEqual(a: ProcessKey | null, b: ProcessKey | null): boolean {
  if (!a || !b) return false
  return processKeyId(a) === processKeyId(b)
}
