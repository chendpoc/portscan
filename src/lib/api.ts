import { invoke } from '@tauri-apps/api/core'
import type { LsofSample, MonitorState, ProcessDetail, ProcessKey, RefreshSettings } from './types'

export function getMonitorState(): Promise<MonitorState> {
  return invoke('get_monitor_state')
}

export function requestRefresh(): Promise<void> {
  return invoke('request_refresh')
}

export function getProcessDetail(key: ProcessKey): Promise<ProcessDetail> {
  return invoke('get_process_detail', { key })
}

export function openProcessTerminal(key: ProcessKey): Promise<void> {
  return invoke('open_process_terminal', { key })
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
