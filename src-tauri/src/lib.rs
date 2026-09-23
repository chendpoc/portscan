mod app_state;
mod collector;
mod commands;
mod diagnostics;
mod error;
mod model;
mod refresh;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            app.manage(app_state::AppState::new());
            refresh::spawn(app.handle().clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::sockets::get_snapshot,
            commands::sockets::refresh_now,
            commands::sockets::diagnose_lsof,
            commands::settings::get_settings,
            commands::settings::update_settings,
        ])
        .run(tauri::generate_context!())
        .expect("error while running portscan");
}
