use std::time::Duration;

use tauri::{AppHandle, Emitter, Manager};

use crate::app_state::AppState;
use crate::collector::{
    associate_pids, normalize, InterfaceInfoCollector, Netstat2Collector, ProcessInfoCollector,
};
use crate::error::CollectorError;
use crate::model::SocketSnapshot;

pub struct RefreshCoordinator {
    netstat: Netstat2Collector,
    processes: ProcessInfoCollector,
    interfaces: InterfaceInfoCollector,
}

impl RefreshCoordinator {
    pub fn new() -> Self {
        Self {
            netstat: Netstat2Collector::default(),
            processes: ProcessInfoCollector::new(),
            interfaces: InterfaceInfoCollector::new(),
        }
    }

    pub fn set_filter(&mut self, include_udp: bool, include_ipv6: bool) {
        self.netstat.set_filter(include_udp, include_ipv6);
    }

    /// netstat2 → raw sockets → PID association → sysinfo → normalize → snapshot
    pub fn refresh(&mut self) -> Result<SocketSnapshot, CollectorError> {
        let raw = self.netstat.collect()?;
        let associated = associate_pids(raw);
        let processes = self.processes.lookup(&associated);
        let sockets = normalize(associated, &processes);
        let interfaces = self.interfaces.collect();
        Ok(SocketSnapshot::new(sockets, interfaces))
    }
}

pub fn spawn(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let wake = app.state::<AppState>().wake_handle();
        loop {
            if !app.state::<AppState>().is_paused() {
                let app_for_refresh = app.clone();
                let joined = tauri::async_runtime::spawn_blocking(move || {
                    app_for_refresh.state::<AppState>().refresh_blocking()
                })
                .await;

                match joined {
                    Ok(Ok(snapshot)) => {
                        let _ = app.emit("snapshot", &snapshot);
                    }
                    Ok(Err(err)) => {
                        tracing::warn!(error = %err, "refresh failed");
                        let _ = app.emit("snapshot-error", err.to_string());
                    }
                    Err(err) => {
                        tracing::warn!(error = %err, "refresh task failed");
                        let _ = app.emit("snapshot-error", err.to_string());
                    }
                }
            }

            let interval = Duration::from_millis(app.state::<AppState>().interval_ms());
            let _ = tokio::time::timeout(interval, wake.notified()).await;
        }
    });
}
