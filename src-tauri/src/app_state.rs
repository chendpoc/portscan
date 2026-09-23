use std::sync::Arc;
use std::sync::{Mutex, MutexGuard};

use tokio::sync::Notify;

use crate::error::AppError;
use crate::model::{RefreshSettings, SocketSnapshot};
use crate::refresh::RefreshCoordinator;

pub struct AppState {
    snapshot: Mutex<SocketSnapshot>,
    settings: Mutex<RefreshSettings>,
    coordinator: Mutex<RefreshCoordinator>,
    wake: Arc<Notify>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            snapshot: Mutex::new(SocketSnapshot::empty()),
            settings: Mutex::new(RefreshSettings::default()),
            coordinator: Mutex::new(RefreshCoordinator::new()),
            wake: Arc::new(Notify::new()),
        }
    }

    pub fn wake_handle(&self) -> Arc<Notify> {
        Arc::clone(&self.wake)
    }

    pub fn snapshot(&self) -> Result<SocketSnapshot, AppError> {
        Ok(self.lock(&self.snapshot)?.clone())
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
        {
            let mut guard = self.lock(&self.settings)?;
            *guard = settings.clone();
        }
        {
            let mut coordinator = self.lock(&self.coordinator)?;
            coordinator.set_filter(settings.include_udp, settings.include_ipv6);
        }
        self.wake.notify_one();
        Ok(settings)
    }

    pub fn refresh_blocking(&self) -> Result<SocketSnapshot, AppError> {
        let settings = self.settings()?;
        let snapshot = {
            let mut coordinator = self.lock(&self.coordinator)?;
            coordinator.set_filter(settings.include_udp, settings.include_ipv6);
            coordinator.refresh()?
        };
        *self.lock(&self.snapshot)? = snapshot.clone();
        Ok(snapshot)
    }

    fn lock<'a, T>(&'a self, mutex: &'a Mutex<T>) -> Result<MutexGuard<'a, T>, AppError> {
        mutex.lock().map_err(|_| AppError::Poisoned)
    }
}
