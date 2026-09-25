import { getProcessDetail } from './api'
import { processKeyId } from './format'
import { createDetailController } from './inspector-detail'
import type { ProcessDetail, ProcessEntry, ProcessKey, PrimaryView, SocketEntry } from './types'

export type InspectorEvidence = {
  key: ProcessKey
  process: ProcessEntry | null
  detail: ProcessDetail | null
  detailError: string | null
  endpoints: SocketEntry[]
  endpointsCapturedAt: string | null
  processCapturedAt: string | null
  socketsCapturedAt: string | null
  exited: boolean
  detailStale: boolean
  detailLoading: boolean
  socketSourceFailed: boolean
  processSourceFailed: boolean
}

type LastGood = {
  process: ProcessEntry | null
  endpoints: SocketEntry[]
  endpointsCapturedAt: string | null
  processCapturedAt: string | null
  detail: ProcessDetail | null
}

type ViewSlot = {
  key: ProcessKey | null
  lastGood: LastGood | null
}

let activeView = $state<PrimaryView>('processes')
let slots = $state<Record<PrimaryView, ViewSlot>>({
  processes: { key: null, lastGood: null },
  ports: { key: null, lastGood: null },
})
let detailRevision = $state(0)
let preview = $state(false)
let socketSourceFailed = $state(false)
let processSourceFailed = $state(false)

const previewDetail = (key: ProcessKey): ProcessDetail => ({
  key,
  command: ['node', 'server.js'],
  exe: '/usr/local/bin/node',
  cwd: { state: 'available', path: '/Users/dev/code/api-red', message: null },
  executable: { state: 'available', path: '/usr/local/bin/node', message: null },
  appBundle: null,
  collectedAt: new Date().toISOString(),
  verifiedAt: new Date().toISOString(),
  ancestry: [
    { key: { pid: 9001, startSec: key.startSec - 100, startUsec: 1 }, name: 'npm', relationshipVerified: true },
    { key: { pid: 9000, startSec: key.startSec - 200, startUsec: 1 }, name: 'zsh', relationshipVerified: true },
    { key: { pid: 8999, startSec: key.startSec - 300, startUsec: 1 }, name: 'Terminal', relationshipVerified: true },
  ],
  ancestryIncomplete: false,
  startTimeIso: new Date(key.startSec * 1000).toISOString(),
})

const controller = createDetailController(
  (key) => (preview ? Promise.resolve(previewDetail(key)) : getProcessDetail(key)),
  () => {
    detailRevision += 1
  },
)

function currentSlot(): ViewSlot {
  return slots[activeView]
}

function writeSlot(next: ViewSlot) {
  slots = { ...slots, [activeView]: next }
}

function buildLastGood(
  process: ProcessEntry | null,
  endpoints: SocketEntry[],
  processCapturedAt: string | null,
  endpointsCapturedAt: string | null,
): LastGood {
  return {
    process,
    endpoints,
    processCapturedAt,
    endpointsCapturedAt,
    detail: null,
  }
}

export const inspectorState = {
  get activeView() {
    return activeView
  },
  get selectedKey() {
    detailRevision
    return currentSlot().key
  },
  get detail() {
    detailRevision
    return controller.state.detail ?? currentSlot().lastGood?.detail ?? null
  },
  get detailError() {
    detailRevision
    return controller.state.detailError
  },
  get detailLoading() {
    detailRevision
    return controller.state.detailLoading
  },
  get detailCapturedAt() {
    detailRevision
    return controller.state.detailCapturedAt
  },
  get lastGood() {
    return currentSlot().lastGood
  },
  setPreview(value: boolean) {
    preview = value
  },
  switchView(view: PrimaryView) {
    if (view === activeView) return
    const previous = currentSlot()
    const detail = controller.state.detail
    if (previous.key && previous.lastGood && detail &&
      processKeyId(detail.key) === processKeyId(previous.key)) {
      writeSlot({ ...previous, lastGood: { ...previous.lastGood, detail } })
    }
    activeView = view
    const slot = currentSlot()
    if (slot.key) {
      controller.select(slot.key)
    } else {
      controller.close()
    }
    detailRevision += 1
  },
  select(
    key: ProcessKey | null,
    process: ProcessEntry | null,
    endpoints: SocketEntry[],
    exited: boolean,
    processCapturedAt: string | null,
    endpointsCapturedAt: string | null,
    socketsFailed: boolean,
    processesFailed: boolean,
  ) {
    const slot = currentSlot()
    if (key && slot.key && processKeyId(slot.key) === processKeyId(key)) return
    socketSourceFailed = socketsFailed
    processSourceFailed = processesFailed
    const lastGood: LastGood | null = key
      ? buildLastGood(process, endpoints, processCapturedAt, endpointsCapturedAt)
      : null
    if (key && exited && lastGood) {
      writeSlot({ key, lastGood: { ...lastGood, process: process ?? lastGood.process } })
    } else {
      writeSlot({ key, lastGood })
    }
    controller.select(key)
  },
  close() {
    writeSlot({ key: null, lastGood: null })
    controller.close()
  },
  syncLastGood(
    findProcess: (key: ProcessKey) => ProcessEntry | undefined,
    endpointsFor: (key: ProcessKey) => SocketEntry[],
    processCapturedAt: string | null,
    socketsCapturedAt: string | null,
    socketsFailed: boolean,
    processesFailed: boolean,
  ) {
    socketSourceFailed = socketsFailed
    processSourceFailed = processesFailed
    const next = { ...slots }
    for (const view of ['processes', 'ports'] as const) {
      const { key, lastGood: previous } = slots[view]
      if (!key) continue
      const live = findProcess(key)
      const currentDetail = controller.state.detail
      const detail = currentDetail && processKeyId(currentDetail.key) === processKeyId(key)
        ? currentDetail : previous?.detail ?? null
      // Exited selections retain the last observation and its original capture time.
      if (!live) {
        if (previous) next[view] = { key, lastGood: { ...previous, detail } }
        continue
      }
      next[view] = {
        key,
        lastGood: {
          process: processesFailed ? previous?.process ?? live : live,
          processCapturedAt: processesFailed
            ? previous?.processCapturedAt ?? processCapturedAt : processCapturedAt,
          endpoints: socketsFailed ? previous?.endpoints ?? endpointsFor(key) : endpointsFor(key),
          endpointsCapturedAt: socketsFailed
            ? previous?.endpointsCapturedAt ?? socketsCapturedAt : socketsCapturedAt,
          detail,
        },
      }
    }
    slots = next
  },
  noteRefreshComplete(cycleGeneration: number) {
    detailRevision
    controller.noteCycle(cycleGeneration)
  },
  evidence(
    liveProcess: ProcessEntry | undefined,
    liveEndpoints: SocketEntry[],
    detailStale: boolean,
    liveProcessCapturedAt: string | null,
    liveSocketsCapturedAt: string | null,
  ): InspectorEvidence | null {
    detailRevision
    const key = currentSlot().key
    if (!key) return null
    const lastGood = currentSlot().lastGood
    const exited = !liveProcess
    const process = liveProcess ?? lastGood?.process ?? null
    const retainHistoricalEndpoints = exited || socketSourceFailed
    const endpoints = retainHistoricalEndpoints ? (lastGood?.endpoints ?? liveEndpoints) : liveEndpoints
    const endpointsCapturedAt = retainHistoricalEndpoints
      ? (lastGood?.endpointsCapturedAt ?? liveSocketsCapturedAt)
      : (liveSocketsCapturedAt ?? lastGood?.endpointsCapturedAt ?? null)
    const processCapturedAt = exited || processSourceFailed
      ? (lastGood?.processCapturedAt ?? liveProcessCapturedAt)
      : (liveProcessCapturedAt ?? lastGood?.processCapturedAt ?? null)
    return {
      key,
      process,
      detail: controller.state.detail ?? lastGood?.detail ?? null,
      detailError: controller.state.detailError,
      endpoints,
      endpointsCapturedAt,
      processCapturedAt,
      socketsCapturedAt: liveSocketsCapturedAt,
      exited,
      detailStale,
      detailLoading: controller.state.detailLoading,
      socketSourceFailed,
      processSourceFailed,
    }
  },
}
