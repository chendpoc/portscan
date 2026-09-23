import { invoke } from '@tauri-apps/api/core'
import type { LsofSample, RefreshSettings, SocketSnapshot } from './types'

export function getSnapshot(): Promise<SocketSnapshot> {
  return invoke('get_snapshot')
}

export function refreshNow(): Promise<SocketSnapshot> {
  return invoke('refresh_now')
}

export function getSettings(): Promise<RefreshSettings> {
  return invoke('get_settings')
}

export function updateSettings(settings: RefreshSettings): Promise<RefreshSettings> {
  return invoke('update_settings', { settings })
}

export function diagnoseLsof(): Promise<LsofSample> {
  return invoke('diagnose_lsof')
}
