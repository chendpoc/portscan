use tauri::State;

use crate::app_state::AppState;
use crate::diagnostics::lsof::{self, LsofSample};
use crate::error::AppError;
use crate::model::SocketSnapshot;

#[tauri::command]
pub fn get_snapshot(state: State<'_, AppState>) -> Result<SocketSnapshot, AppError> {
    state.snapshot()
}

#[tauri::command]
pub fn refresh_now(state: State<'_, AppState>) -> Result<SocketSnapshot, AppError> {
    state.refresh_blocking()
}

#[tauri::command]
pub fn diagnose_lsof() -> Result<LsofSample, AppError> {
    lsof::sample().map_err(AppError::Message)
}
