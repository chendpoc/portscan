import type {
  MonitorState,
  ProcessSnapshot,
  RefreshFatal,
  SnapshotError,
  SocketSnapshot,
} from './types'

export type SourceGenerationState = {
  processSeen: number
  socketSeen: number
}

export function shouldAcceptSnapshot(seenGeneration: number, snapshotGeneration: number): boolean {
  return snapshotGeneration >= seenGeneration
}

export function applyProcessSnapshot(
  state: SourceGenerationState,
  snapshot: ProcessSnapshot,
): { state: SourceGenerationState; accepted: boolean } {
  if (!shouldAcceptSnapshot(state.processSeen, snapshot.generation)) {
    return { state, accepted: false }
  }
  return {
    state: { ...state, processSeen: snapshot.generation },
    accepted: true,
  }
}

export function applySocketSnapshot(
  state: SourceGenerationState,
  snapshot: SocketSnapshot,
): { state: SourceGenerationState; accepted: boolean } {
  if (!shouldAcceptSnapshot(state.socketSeen, snapshot.generation)) {
    return { state, accepted: false }
  }
  return {
    state: { ...state, socketSeen: snapshot.generation },
    accepted: true,
  }
}

export function applyProcessError(
  state: SourceGenerationState,
  error: SnapshotError,
): SourceGenerationState {
  if (error.generation < state.processSeen) return state
  return { ...state, processSeen: Math.max(state.processSeen, error.generation) }
}

export function shouldApplyProcessErrorMessage(
  state: SourceGenerationState,
  error: SnapshotError,
): boolean {
  return error.generation >= state.processSeen
}

export function reduceProcessErrorEvent(
  state: SourceGenerationState,
  error: SnapshotError,
): { state: SourceGenerationState; message: string | null } {
  if (error.generation < state.processSeen) {
    return { state, message: null }
  }
  const next = applyProcessError(state, error)
  return { state: next, message: error.message }
}

export function reduceSocketErrorEvent(
  state: SourceGenerationState,
  error: SnapshotError,
): { state: SourceGenerationState; message: string | null } {
  if (error.generation < state.socketSeen) {
    return { state, message: null }
  }
  const next = {
    ...state,
    socketSeen: Math.max(state.socketSeen, error.generation),
  }
  return { state: next, message: error.message }
}

export type MonitorViewModel = {
  processes: ProcessSnapshot | null
  sockets: SocketSnapshot | null
  processError: string | null
  socketError: string | null
}

export function applyBootstrapMonitorState(
  state: SourceGenerationState,
  monitor: MonitorViewModel,
  initial: MonitorState,
): { state: SourceGenerationState; monitor: MonitorViewModel } {
  let nextState = state
  let nextMonitor = { ...monitor }

  if (initial.processes) {
    const applied = applyProcessSnapshot(nextState, initial.processes)
    nextState = applied.state
    if (applied.accepted) {
      nextMonitor.processes = initial.processes
      nextMonitor.processError = null
    }
  }

  if (initial.sockets) {
    const applied = applySocketSnapshot(nextState, initial.sockets)
    nextState = applied.state
    if (applied.accepted) {
      nextMonitor.sockets = initial.sockets
      nextMonitor.socketError = null
    }
  }

  const processErrorGen = initial.processErrorGeneration ?? null
  if (initial.processError && processErrorGen != null) {
    const reduced = reduceProcessErrorEvent(nextState, {
      generation: processErrorGen,
      message: initial.processError,
    })
    nextState = reduced.state
    if (reduced.message) nextMonitor.processError = reduced.message
  } else if (initial.processError && !initial.processes) {
    nextMonitor.processError = initial.processError
  }

  const socketErrorGen = initial.socketErrorGeneration ?? null
  if (initial.socketError && socketErrorGen != null) {
    const reduced = reduceSocketErrorEvent(nextState, {
      generation: socketErrorGen,
      message: initial.socketError,
    })
    nextState = reduced.state
    if (reduced.message) nextMonitor.socketError = reduced.message
  } else if (initial.socketError && !initial.sockets) {
    nextMonitor.socketError = initial.socketError
  }

  return { state: nextState, monitor: nextMonitor }
}

export function shouldClearFatalError(
  fatalGeneration: number,
  refreshCompleteGeneration: number,
): boolean {
  return refreshCompleteGeneration >= fatalGeneration
}

export function monitorCycleGeneration(initial: MonitorState): number {
  let generation = 0
  if (initial.processes) generation = Math.max(generation, initial.processes.generation)
  if (initial.sockets) generation = Math.max(generation, initial.sockets.generation)
  if (initial.processErrorGeneration != null) {
    generation = Math.max(generation, initial.processErrorGeneration)
  }
  if (initial.socketErrorGeneration != null) {
    generation = Math.max(generation, initial.socketErrorGeneration)
  }
  return generation
}

export function reduceRefreshComplete(
  cycleSeen: number,
  generation: number,
  sourceSeen: number,
): { cycleSeen: number; accepted: boolean } {
  if (generation <= cycleSeen || generation < sourceSeen) {
    return { cycleSeen, accepted: false }
  }
  return { cycleSeen: generation, accepted: true }
}

export function reduceRefreshFatal(
  cycleSeen: number,
  fatal: RefreshFatal,
  sourceSeen: number,
): { cycleSeen: number; accepted: boolean; message: string | null } {
  if (fatal.generation <= cycleSeen || fatal.generation < sourceSeen) {
    return { cycleSeen, accepted: false, message: null }
  }
  return {
    cycleSeen: Math.max(cycleSeen, fatal.generation),
    accepted: true,
    message: fatal.message,
  }
}
