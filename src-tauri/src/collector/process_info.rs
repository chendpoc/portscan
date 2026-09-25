use std::collections::HashMap;
use std::time::Instant;

use sysinfo::{
    Pid, ProcessRefreshKind, ProcessStatus, ProcessesToUpdate, System, UpdateKind,
    MINIMUM_CPU_UPDATE_INTERVAL,
};

use chrono::Utc;

use super::macos_context::{app_bundle_from_executable, read_process_context};
use super::macos_identity::{process_start, ProcessStart};
use crate::error::{AppError, CollectorError};
use crate::model::{
    AncestryNode, ProcessDetail, ProcessEntry, ProcessKey, ProcessSnapshot, ProcessState,
};

pub struct ProcessInfoCollector {
    system: System,
    previous_keys: HashMap<u32, ProcessKey>,
    last_sample_at: Option<Instant>,
}

impl ProcessInfoCollector {
    pub fn new() -> Self {
        Self {
            system: System::new(),
            previous_keys: HashMap::new(),
            last_sample_at: None,
        }
    }

    pub fn sample(&mut self, generation: u64) -> Result<ProcessSnapshot, CollectorError> {
        let sample_ready = self
            .last_sample_at
            .is_some_and(|last| last.elapsed() >= MINIMUM_CPU_UPDATE_INTERVAL);
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().with_cpu().with_memory(),
        );
        if self
            .system
            .process(Pid::from_u32(std::process::id()))
            .is_none()
        {
            return Err(CollectorError::Process(
                "当前进程未出现在进程枚举结果中".into(),
            ));
        }

        let mut entries = Vec::with_capacity(self.system.processes().len());
        let mut current_keys = HashMap::with_capacity(self.system.processes().len());
        for (pid, process) in self.system.processes() {
            let pid = pid.as_u32();
            let start_sec = process.start_time();
            let start_usec = process_start(pid)
                .filter(|start| start.seconds == start_sec)
                .map(|start| start.microseconds);
            let key = ProcessKey {
                pid,
                start_sec,
                start_usec,
            };
            let cpu_percent =
                cpu_sample_ready(self.previous_keys.get(&pid).copied(), key, sample_ready)
                    .then(|| process.cpu_usage())
                    .filter(|value| value.is_finite());
            let context = read_process_context(key);
            entries.push(ProcessEntry {
                key,
                name: process.name().to_string_lossy().into_owned(),
                cpu_percent,
                rss_bytes: Some(process.memory()),
                status: process_state(process.status()),
                parent_pid: process.parent().map(|parent| parent.as_u32()),
                cwd: context.cwd,
                executable: context.executable,
                context_display: context.context_display,
                context_kind: context.context_kind,
            });
            current_keys.insert(pid, key);
        }
        self.previous_keys = current_keys;
        self.last_sample_at = Some(Instant::now());
        Ok(ProcessSnapshot::new(generation, entries))
    }
}

/// A detail request never returns data for a later process that reused the PID.
pub fn process_detail(key: ProcessKey) -> Result<ProcessDetail, AppError> {
    let expected = match key.start_usec {
        Some(microseconds) => ProcessStart {
            seconds: key.start_sec,
            microseconds,
        },
        None => return Err(AppError::Message("Process identity is unavailable".into())),
    };
    if process_start(key.pid) != Some(expected) {
        return Err(AppError::Message("Process exited or changed".into()));
    }
    let mut system = System::new();
    let pid = Pid::from_u32(key.pid);
    system.refresh_processes_specifics(
        ProcessesToUpdate::Some(&[pid]),
        true,
        ProcessRefreshKind::nothing()
            .with_cmd(UpdateKind::Always)
            .with_exe(UpdateKind::Always),
    );
    let process = system
        .process(pid)
        .filter(|process| process.start_time() == key.start_sec)
        .ok_or_else(|| AppError::Message("Process exited or changed".into()))?;
    let command: Vec<String> = process
        .cmd()
        .iter()
        .map(|arg| arg.to_string_lossy().into_owned())
        .collect();
    let exe = process
        .exe()
        .map(|path| path.to_string_lossy().into_owned())
        .filter(|path| !path.is_empty());
    if process_start(key.pid) != Some(expected) {
        return Err(AppError::Message("Process exited or changed".into()));
    }
    let collected_at = Utc::now();
    let context = read_process_context(key);
    if process_start(key.pid) != Some(expected) {
        return Err(AppError::Message("Process exited or changed".into()));
    }
    let verified_at = Utc::now();
    let app_bundle = exe.as_deref().and_then(app_bundle_from_executable);
    let (ancestry, ancestry_incomplete) = collect_ancestry(key, &mut system);
    if process_start(key.pid) != Some(expected) {
        return Err(AppError::Message("Process exited or changed".into()));
    }
    Ok(ProcessDetail {
        key,
        command: (!command.is_empty()).then_some(command),
        exe,
        cwd: context.cwd,
        executable: context.executable,
        app_bundle,
        collected_at: collected_at.to_rfc3339(),
        verified_at: verified_at.to_rfc3339(),
        ancestry,
        ancestry_incomplete,
        start_time_iso: Some(
            chrono::DateTime::<Utc>::from_timestamp(key.start_sec as i64, 0)
                .map(|value| value.to_rfc3339())
                .unwrap_or_default(),
        ),
    })
}

fn identity_for_key(key: ProcessKey) -> Option<ProcessStart> {
    key.start_usec.and_then(|microseconds| {
        process_start(key.pid)
            .filter(|start| start.seconds == key.start_sec && start.microseconds == microseconds)
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ProcessObservation {
    key: ProcessKey,
    name: String,
    parent_pid: Option<u32>,
}

fn parent_key_for_pid(pid: u32) -> Option<ProcessKey> {
    process_start(pid).map(|start| ProcessKey {
        pid,
        start_sec: start.seconds,
        start_usec: Some(start.microseconds),
    })
}

fn observe_process(key: ProcessKey, system: &mut System) -> Option<ProcessObservation> {
    let expected = identity_for_key(key)?;
    system.refresh_processes_specifics(
        ProcessesToUpdate::Some(&[Pid::from_u32(key.pid)]),
        true,
        ProcessRefreshKind::nothing().with_memory(),
    );
    let process = system.process(Pid::from_u32(key.pid))?;
    if identity_for_key(key) != Some(expected) {
        return None;
    }
    let name = process.name().to_string_lossy().into_owned();
    let parent_pid = process.parent().map(|parent| parent.as_u32());
    Some(ProcessObservation {
        key,
        name,
        parent_pid,
    })
}

fn verify_parent_edge(child: ProcessKey, parent_key: ProcessKey, system: &mut System) -> bool {
    let Some(child_expected) = identity_for_key(child) else {
        return false;
    };
    let Some(parent_expected) = identity_for_key(parent_key) else {
        return false;
    };
    let Some(child_obs) = observe_process(child, system) else {
        return false;
    };
    if child_obs.parent_pid != Some(parent_key.pid) {
        return false;
    }
    let Some(parent_obs) = observe_process(parent_key, system) else {
        return false;
    };
    identity_for_key(child) == Some(child_expected)
        && identity_for_key(parent_key) == Some(parent_expected)
        && child_obs.parent_pid == Some(parent_key.pid)
        && parent_obs.key == parent_key
}

trait AncestryReader {
    fn observe(&mut self, key: ProcessKey) -> Option<ProcessObservation>;
    fn verify_parent_edge(&mut self, child: ProcessKey, parent: ProcessKey) -> bool;
}

struct SystemAncestryReader<'a> {
    system: &'a mut System,
}

impl AncestryReader for SystemAncestryReader<'_> {
    fn observe(&mut self, key: ProcessKey) -> Option<ProcessObservation> {
        observe_process(key, self.system)
    }

    fn verify_parent_edge(&mut self, child: ProcessKey, parent: ProcessKey) -> bool {
        verify_parent_edge(child, parent, self.system)
    }
}

fn collect_ancestry_from_observations(
    selected: ProcessKey,
    reader: &mut dyn AncestryReader,
    mut resolve_parent: impl FnMut(u32) -> Option<ProcessKey>,
) -> (Vec<AncestryNode>, bool) {
    let mut nodes = Vec::new();
    let mut incomplete = false;
    let Some(selected_obs) = reader.observe(selected) else {
        return (nodes, true);
    };
    let Some(mut parent_pid) = selected_obs.parent_pid else {
        return (nodes, false);
    };
    let mut child_key = selected;
    for _ in 0..8 {
        let Some(parent_key) = resolve_parent(parent_pid) else {
            incomplete = true;
            break;
        };
        if parent_key == selected {
            incomplete = true;
            break;
        }
        if nodes.iter().any(|node| node.key == parent_key) {
            incomplete = true;
            break;
        }
        if !reader.verify_parent_edge(child_key, parent_key) {
            incomplete = true;
            break;
        }
        let Some(parent_obs) = reader.observe(parent_key) else {
            incomplete = true;
            break;
        };
        nodes.push(AncestryNode {
            key: parent_key,
            name: parent_obs.name,
            relationship_verified: true,
        });
        let Some(next_parent) = parent_obs.parent_pid else {
            break;
        };
        child_key = parent_key;
        parent_pid = next_parent;
    }
    if nodes.len() >= 8 {
        incomplete = true;
    }
    (nodes, incomplete)
}

fn collect_ancestry(key: ProcessKey, system: &mut System) -> (Vec<AncestryNode>, bool) {
    let mut reader = SystemAncestryReader { system };
    collect_ancestry_from_observations(key, &mut reader, parent_key_for_pid)
}

fn cpu_sample_ready(previous: Option<ProcessKey>, current: ProcessKey, spaced: bool) -> bool {
    spaced && previous == Some(current)
}

fn process_state(status: ProcessStatus) -> ProcessState {
    match status {
        ProcessStatus::Run => ProcessState::Running,
        ProcessStatus::Sleep => ProcessState::Sleeping,
        ProcessStatus::Stop | ProcessStatus::Suspended => ProcessState::Stopped,
        ProcessStatus::Zombie | ProcessStatus::Dead => ProcessState::Zombie,
        _ => ProcessState::Unknown,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    struct CallbackAncestryReader {
        observe: Box<dyn FnMut(ProcessKey) -> Option<ProcessObservation>>,
        verify: Box<dyn FnMut(ProcessKey, ProcessKey) -> bool>,
    }

    impl AncestryReader for CallbackAncestryReader {
        fn observe(&mut self, key: ProcessKey) -> Option<ProcessObservation> {
            (self.observe)(key)
        }

        fn verify_parent_edge(&mut self, child: ProcessKey, parent: ProcessKey) -> bool {
            (self.verify)(child, parent)
        }
    }

    #[test]
    fn all_process_scan_includes_self_and_starts_cpu_as_unknown() {
        let mut collector = ProcessInfoCollector::new();
        let snapshot = collector
            .sample(1)
            .expect("process enumeration should work");
        let current = snapshot
            .entries
            .iter()
            .find(|entry| entry.key.pid == std::process::id())
            .expect("current process should be visible");
        assert!(!current.name.is_empty());
        assert!(current.cpu_percent.is_none());
        assert!(snapshot.entries.len() > 1);
    }

    #[test]
    fn cpu_requires_two_spaced_samples_of_the_same_process_instance() {
        let old = ProcessKey {
            pid: 10,
            start_sec: 100,
            start_usec: Some(1),
        };
        let replacement = ProcessKey {
            start_usec: Some(2),
            ..old
        };
        assert!(!cpu_sample_ready(None, old, true));
        assert!(!cpu_sample_ready(Some(old), replacement, true));
        assert!(!cpu_sample_ready(Some(old), old, false));
        assert!(cpu_sample_ready(Some(old), old, true));
    }

    #[test]
    fn detail_refuses_an_unverified_process_instance() {
        let key = ProcessKey {
            pid: std::process::id(),
            start_sec: 1,
            start_usec: None,
        };
        assert!(process_detail(key).is_err());
    }

    fn key(pid: u32, sec: u64, usec: u64) -> ProcessKey {
        ProcessKey {
            pid,
            start_sec: sec,
            start_usec: Some(usec),
        }
    }

    #[test]
    fn ancestry_stops_when_parent_edge_is_not_verified() {
        let selected = key(10, 100, 1);
        let parent_a = key(9, 90, 5);
        let parent_b = key(9, 90, 6);
        let mut reader = CallbackAncestryReader {
            observe: Box::new(move |k| {
                if k == selected {
                    Some(ProcessObservation {
                        key: selected,
                        name: "child".into(),
                        parent_pid: Some(9),
                    })
                } else if k == parent_a {
                    Some(ProcessObservation {
                        key: parent_a,
                        name: "parent".into(),
                        parent_pid: None,
                    })
                } else {
                    None
                }
            }),
            verify: Box::new(move |_, parent| parent == parent_a),
        };
        let (nodes, incomplete) =
            collect_ancestry_from_observations(selected, &mut reader, |pid| {
                if pid == 9 {
                    Some(parent_b)
                } else {
                    None
                }
            });
        assert_eq!(nodes.len(), 0);
        assert!(incomplete);
    }

    #[test]
    fn ancestry_excludes_selected_and_detects_cycle() {
        let selected = key(5, 50, 1);
        let parent = key(4, 40, 1);
        let grand = key(3, 30, 1);
        let mut reader = CallbackAncestryReader {
            observe: Box::new(move |k| match k.pid {
                5 => Some(ProcessObservation {
                    key: selected,
                    name: "sel".into(),
                    parent_pid: Some(4),
                }),
                4 => Some(ProcessObservation {
                    key: parent,
                    name: "p".into(),
                    parent_pid: Some(3),
                }),
                3 => Some(ProcessObservation {
                    key: grand,
                    name: "g".into(),
                    parent_pid: Some(4),
                }),
                _ => None,
            }),
            verify: Box::new(|_, _| true),
        };
        let (nodes, incomplete) =
            collect_ancestry_from_observations(selected, &mut reader, |pid| match pid {
                4 => Some(parent),
                3 => Some(grand),
                _ => None,
            });
        assert!(nodes.iter().all(|node| node.key.pid != selected.pid));
        assert!(incomplete);
        assert_eq!(nodes.len(), 2);
    }

    #[test]
    fn ancestry_carries_verified_parent_key_not_reused_pid() {
        let selected = key(20, 200, 1);
        let verified_parent = key(19, 190, 7);
        let mut reader = CallbackAncestryReader {
            observe: Box::new(move |k| {
                if k == selected {
                    Some(ProcessObservation {
                        key: selected,
                        name: "worker".into(),
                        parent_pid: Some(19),
                    })
                } else if k == verified_parent {
                    Some(ProcessObservation {
                        key: verified_parent,
                        name: "supervisor".into(),
                        parent_pid: None,
                    })
                } else {
                    None
                }
            }),
            verify: Box::new(move |child, parent| child == selected && parent == verified_parent),
        };
        let (nodes, incomplete) =
            collect_ancestry_from_observations(selected, &mut reader, |pid| {
                if pid == 19 {
                    Some(verified_parent)
                } else {
                    None
                }
            });
        assert!(!incomplete);
        assert_eq!(nodes.len(), 1);
        assert_eq!(nodes[0].key, verified_parent);
    }

    #[test]
    fn second_spaced_sample_and_on_demand_detail_use_same_instance() {
        let mut collector = ProcessInfoCollector::new();
        let first = collector.sample(1).expect("first scan should work");
        let initial = first
            .entries
            .iter()
            .find(|entry| entry.key.pid == std::process::id())
            .expect("current process should be visible");
        let key = initial.key;
        assert!(initial.cpu_percent.is_none());
        std::thread::sleep(MINIMUM_CPU_UPDATE_INTERVAL + Duration::from_millis(50));
        let second = collector.sample(2).expect("second scan should work");
        let current = second
            .entries
            .iter()
            .find(|entry| entry.key.pid == std::process::id())
            .expect("current process should remain visible");
        assert_eq!(current.key, key);
        assert!(current.cpu_percent.is_some());
        let detail = process_detail(key).expect("current process detail should be available");
        assert_eq!(detail.key, key);
    }
}
