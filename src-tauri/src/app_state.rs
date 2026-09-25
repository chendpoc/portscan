use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::{Mutex, MutexGuard};

use tokio::sync::Notify;

use crate::collector::ProcessInfoCollector;
use crate::error::AppError;
use crate::model::{MonitorState, ProcessSnapshot, RefreshSettings, SocketSnapshot};
use crate::refresh::RefreshCoordinator;

pub struct RefreshOutcome {
    pub generation: u64,
    pub processes: Result<ProcessSnapshot, String>,
    pub sockets: Result<SocketSnapshot, String>,
}

pub struct AppState {
    monitor: Mutex<MonitorState>,
    settings: Mutex<RefreshSettings>,
    processes: Mutex<ProcessInfoCollector>,
    sockets: Mutex<RefreshCoordinator>,
    wake: Arc<Notify>,
    manual_requested: AtomicBool,
    next_generation: AtomicU64,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            monitor: Mutex::new(MonitorState::default()),
            settings: Mutex::new(RefreshSettings::default()),
            processes: Mutex::new(ProcessInfoCollector::new()),
            sockets: Mutex::new(RefreshCoordinator::new()),
            wake: Arc::new(Notify::new()),
            manual_requested: AtomicBool::new(false),
            next_generation: AtomicU64::new(1),
        }
    }

    pub fn wake_handle(&self) -> Arc<Notify> {
        Arc::clone(&self.wake)
    }

    pub fn monitor_state(&self) -> Result<MonitorState, AppError> {
        Ok(self.lock(&self.monitor)?.clone())
    }

    pub fn settings(&self) -> Result<RefreshSettings, AppError> {
        Ok(self.lock(&self.settings)?.clone())
    }

    pub fn is_paused(&self) -> bool {
        self.settings
            .lock()
            .map(|settings| settings.paused)
            .unwrap_or(true)
    }

    pub fn interval_ms(&self) -> u64 {
        self.settings
            .lock()
            .map(|settings| settings.interval_ms.clamp(500, 30_000))
            .unwrap_or(2_000)
    }

    pub fn update_settings(
        &self,
        mut settings: RefreshSettings,
    ) -> Result<RefreshSettings, AppError> {
        settings.interval_ms = settings.interval_ms.clamp(500, 30_000);
        *self.lock(&self.settings)? = settings.clone();
        self.wake.notify_one();
        Ok(settings)
    }

    pub fn request_refresh(&self) {
        self.manual_requested.store(true, Ordering::Release);
        self.wake.notify_one();
    }

    pub fn take_manual_request(&self) -> bool {
        self.manual_requested.swap(false, Ordering::AcqRel)
    }

    pub fn allocate_generation(&self) -> u64 {
        self.next_generation.fetch_add(1, Ordering::Relaxed)
    }

    /// Each source has an independent success/error result and last-good cache.
    pub fn refresh_blocking(&self, generation: u64) -> Result<RefreshOutcome, AppError> {
        let settings = self.settings()?;
        let processes = self
            .lock(&self.processes)
            .and_then(|mut collector| collector.sample(generation).map_err(AppError::from))
            .map_err(|error| error.to_string());
        {
            let mut monitor = self.lock(&self.monitor)?;
            match &processes {
                Ok(snapshot) => {
                    monitor.processes = Some(snapshot.clone());
                    monitor.process_error = None;
                    monitor.process_error_generation = None;
                }
                Err(error) => {
                    monitor.process_error = Some(error.clone());
                    monitor.process_error_generation = Some(generation);
                }
            }
        }

        let known_processes = self
            .lock(&self.monitor)?
            .processes
            .as_ref()
            .map(|snapshot| snapshot.entries.clone())
            .unwrap_or_default();
        let sockets = self
            .lock(&self.sockets)
            .and_then(|mut collector| {
                collector.set_filter(settings.include_udp, settings.include_ipv6);
                collector
                    .refresh(generation, &known_processes)
                    .map_err(AppError::from)
            })
            .map_err(|error| error.to_string());
        {
            let mut monitor = self.lock(&self.monitor)?;
            match &sockets {
                Ok(snapshot) => {
                    monitor.sockets = Some(snapshot.clone());
                    monitor.socket_error = None;
                    monitor.socket_error_generation = None;
                }
                Err(error) => {
                    monitor.socket_error = Some(error.clone());
                    monitor.socket_error_generation = Some(generation);
                }
            }
        }
        Ok(RefreshOutcome {
            generation,
            processes,
            sockets,
        })
    }

    fn lock<'a, T>(&'a self, mutex: &'a Mutex<T>) -> Result<MutexGuard<'a, T>, AppError> {
        mutex.lock().map_err(|_| AppError::Poisoned)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn live_refresh_keeps_processes_independent_from_socket_rows() {
        let state = AppState::new();
        let generation = state.allocate_generation();
        let outcome = state
            .refresh_blocking(generation)
            .expect("refresh should run");
        let processes = outcome.processes.expect("process scan should succeed");
        let sockets = outcome.sockets.expect("socket scan should succeed");
        let self_pid = std::process::id();
        assert!(processes
            .entries
            .iter()
            .any(|entry| entry.key.pid == self_pid));
        assert!(processes.entries.len() > 1);
        assert_eq!(sockets.generation, processes.generation);
        let cached = state.monitor_state().expect("cache should be readable");
        assert!(cached.processes.is_some());
        assert!(cached.sockets.is_some());
        assert!(cached.process_error.is_none());
        assert!(cached.socket_error.is_none());
    }
}
