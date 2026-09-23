use tauri::State;

use crate::app_state::AppState;
use crate::error::AppError;
use crate::model::RefreshSettings;

#[tauri::command]
pub fn get_settings(state: State<'_, AppState>) -> Result<RefreshSettings, AppError> {
    state.settings()
}

#[tauri::command]
pub fn update_settings(
    state: State<'_, AppState>,
    settings: RefreshSettings,
) -> Result<RefreshSettings, AppError> {
    state.update_settings(settings)
}
