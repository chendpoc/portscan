use tauri::State;

use crate::app_state::AppState;
use crate::diagnostics::lsof::{self, LsofSample};
use crate::error::AppError;
use crate::model::MonitorState;

#[tauri::command]
pub fn get_monitor_state(state: State<'_, AppState>) -> Result<MonitorState, AppError> {
    state.monitor_state()
}

#[tauri::command]
pub fn request_refresh(state: State<'_, AppState>) {
    state.request_refresh();
}

#[tauri::command]
pub fn diagnose_lsof() -> Result<LsofSample, AppError> {
    lsof::sample().map_err(AppError::Message)
}
