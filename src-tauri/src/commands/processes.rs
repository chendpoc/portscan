use std::process::Command;

use crate::collector::{process_detail, verified_cwd_for_terminal};
use crate::error::AppError;
use crate::model::{ProcessDetail, ProcessKey};

#[tauri::command]
pub async fn get_process_detail(key: ProcessKey) -> Result<ProcessDetail, AppError> {
    tauri::async_runtime::spawn_blocking(move || process_detail(key))
        .await
        .map_err(|error| AppError::Message(error.to_string()))?
}

#[tauri::command]
pub async fn open_process_terminal(key: ProcessKey) -> Result<(), AppError> {
    tauri::async_runtime::spawn_blocking(move || open_terminal(key))
        .await
        .map_err(|error| AppError::Message(error.to_string()))?
}

pub fn build_terminal_command(cwd: &str) -> Command {
    let mut command = Command::new("/usr/bin/open");
    command.arg("-a").arg("Terminal").arg(cwd);
    command
}

fn open_terminal(key: ProcessKey) -> Result<(), AppError> {
    let cwd = verified_cwd_for_terminal(key).map_err(AppError::Message)?;
    let status = build_terminal_command(&cwd)
        .status()
        .map_err(|error| AppError::Message(error.to_string()))?;
    if status.success() {
        Ok(())
    } else {
        Err(AppError::Message(format!(
            "Terminal failed to open for {}",
            cwd
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_command_uses_fixed_arguments_without_shell() {
        let key = ProcessKey {
            pid: std::process::id(),
            start_sec: 1,
            start_usec: Some(1),
        };
        assert!(open_terminal(key).is_err());
    }

    #[test]
    fn terminal_open_passes_directory_as_single_argument() {
        for cwd in [
            "/tmp/spaced dir",
            "/tmp/quote\"dir",
            "/tmp/unicode-进程",
            "/tmp/;rm -rf /",
        ] {
            let command = build_terminal_command(cwd);
            let args: Vec<_> = command
                .get_args()
                .map(|value| value.to_string_lossy().into_owned())
                .collect();
            assert_eq!(args, vec!["-a", "Terminal", cwd]);
        }
    }
}
