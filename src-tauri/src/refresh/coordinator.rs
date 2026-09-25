use std::collections::{HashMap, HashSet};
use std::time::Duration;

use tauri::{AppHandle, Emitter, Manager};

use crate::app_state::AppState;
use crate::collector::{
    associate_pids, normalize, process_start, InterfaceInfoCollector, Netstat2Collector,
};
use crate::error::CollectorError;
use crate::model::{ProcessEntry, RefreshFatal, SnapshotError, SocketSnapshot};

pub struct RefreshCoordinator {
    netstat: Netstat2Collector,
    interfaces: InterfaceInfoCollector,
}

impl RefreshCoordinator {
    pub fn new() -> Self {
        Self {
            netstat: Netstat2Collector::default(),
            interfaces: InterfaceInfoCollector::new(),
        }
    }

    pub fn set_filter(&mut self, include_udp: bool, include_ipv6: bool) {
        self.netstat.set_filter(include_udp, include_ipv6);
    }

    /// Socket facts remain valid even when process metadata is unavailable.
    pub fn refresh(
        &mut self,
        generation: u64,
        process_entries: &[ProcessEntry],
    ) -> Result<SocketSnapshot, CollectorError> {
        let raw = self.netstat.collect()?;
        let associated = associate_pids(raw);
        let socket_pids: HashSet<u32> = associated.iter().filter_map(|entry| entry.pid).collect();
        let processes: HashMap<u32, ProcessEntry> = process_entries
            .iter()
            .filter(|entry| socket_pids.contains(&entry.key.pid))
            .filter(|entry| {
                entry.key.start_usec.is_some_and(|microseconds| {
                    process_start(entry.key.pid).is_some_and(|start| {
                        start.seconds == entry.key.start_sec && start.microseconds == microseconds
                    })
                })
            })
            .map(|entry| (entry.key.pid, entry.clone()))
            .collect();
        let sockets = normalize(associated, &processes);
        let interfaces = self.interfaces.collect();
        Ok(SocketSnapshot::new(generation, sockets, interfaces))
    }
}

pub fn spawn(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let wake = app.state::<AppState>().wake_handle();
        loop {
            let manual = app.state::<AppState>().take_manual_request();
            if !app.state::<AppState>().is_paused() || manual {
                let generation = app.state::<AppState>().allocate_generation();
                let app_for_refresh = app.clone();
                let joined = tauri::async_runtime::spawn_blocking(move || {
                    app_for_refresh
                        .state::<AppState>()
                        .refresh_blocking(generation)
                })
                .await;

                match joined {
                    Ok(Ok(outcome)) => {
                        match outcome.processes {
                            Ok(snapshot) => {
                                let _ = app.emit("process-snapshot", &snapshot);
                            }
                            Err(message) => {
                                tracing::warn!(error = %message, "process refresh failed");
                                let _ = app.emit(
                                    "process-error",
                                    SnapshotError {
                                        generation: outcome.generation,
                                        message,
                                    },
                                );
                            }
                        }
                        match outcome.sockets {
                            Ok(snapshot) => {
                                let _ = app.emit("snapshot", &snapshot);
                            }
                            Err(message) => {
                                tracing::warn!(error = %message, "socket refresh failed");
                                let _ = app.emit(
                                    "snapshot-error",
                                    SnapshotError {
                                        generation: outcome.generation,
                                        message,
                                    },
                                );
                            }
                        }
                        let _ = app.emit("refresh-complete", outcome.generation);
                    }
                    Ok(Err(err)) => {
                        tracing::warn!(error = %err, "refresh failed");
                        let _ = app.emit(
                            "refresh-fatal",
                            RefreshFatal {
                                generation,
                                message: err.to_string(),
                            },
                        );
                    }
                    Err(err) => {
                        tracing::warn!(error = %err, "refresh task failed");
                        let _ = app.emit(
                            "refresh-fatal",
                            RefreshFatal {
                                generation,
                                message: err.to_string(),
                            },
                        );
                    }
                }
            }

            let interval = Duration::from_millis(app.state::<AppState>().interval_ms());
            let _ = tokio::time::timeout(interval, wake.notified()).await;
        }
    });
}
