use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::interface::InterfaceInfo;
use super::process::ProcessEntry;
use super::socket::{SocketEntry, SocketState};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SocketSnapshot {
    pub generation: u64,
    pub captured_at: DateTime<Utc>,
    pub sockets: Vec<SocketEntry>,
    pub interfaces: Vec<InterfaceInfo>,
}

impl SocketSnapshot {
    pub fn new(
        generation: u64,
        mut sockets: Vec<SocketEntry>,
        mut interfaces: Vec<InterfaceInfo>,
    ) -> Self {
        sockets.sort_by(|left, right| {
            state_rank(left.state)
                .cmp(&state_rank(right.state))
                .then(left.local_port.cmp(&right.local_port))
                .then(left.process_name.cmp(&right.process_name))
                .then(left.pid.cmp(&right.pid))
        });
        interfaces.sort_by(|left, right| left.name.cmp(&right.name));
        Self {
            generation,
            captured_at: Utc::now(),
            sockets,
            interfaces,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessSnapshot {
    pub generation: u64,
    pub captured_at: DateTime<Utc>,
    pub entries: Vec<ProcessEntry>,
}

impl ProcessSnapshot {
    pub fn new(generation: u64, mut entries: Vec<ProcessEntry>) -> Self {
        entries.sort_by_key(|entry| entry.key.pid);
        Self {
            generation,
            captured_at: Utc::now(),
            entries,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MonitorState {
    pub processes: Option<ProcessSnapshot>,
    pub sockets: Option<SocketSnapshot>,
    pub process_error: Option<String>,
    pub socket_error: Option<String>,
    pub process_error_generation: Option<u64>,
    pub socket_error_generation: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotError {
    pub generation: u64,
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshFatal {
    pub generation: u64,
    pub message: String,
}

fn state_rank(state: SocketState) -> u8 {
    match state {
        SocketState::Listen => 0,
        SocketState::Established => 1,
        SocketState::SynSent | SocketState::SynReceived => 2,
        SocketState::None => 4,
        _ => 3,
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshSettings {
    pub interval_ms: u64,
    pub paused: bool,
    pub include_udp: bool,
    pub include_ipv6: bool,
}

impl Default for RefreshSettings {
    fn default() -> Self {
        Self {
            interval_ms: 2_000,
            paused: false,
            include_udp: true,
            include_ipv6: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::socket::{Protocol, SocketEntry, SocketState};

    fn entry(state: SocketState, port: u16) -> SocketEntry {
        SocketEntry {
            pid: Some(1),
            process_key: None,
            process_name: Some("a".into()),
            protocol: Protocol::Tcp,
            state,
            local_address: "127.0.0.1".into(),
            local_port: port,
            remote_address: None,
            remote_port: None,
        }
    }

    #[test]
    fn listen_sorts_before_established() {
        let snapshot = SocketSnapshot::new(
            1,
            vec![
                entry(SocketState::Established, 10),
                entry(SocketState::Listen, 80),
            ],
            vec![],
        );
        assert_eq!(snapshot.sockets[0].state, SocketState::Listen);
        assert_eq!(snapshot.sockets[1].state, SocketState::Established);
    }

    #[test]
    fn serializes_process_metrics_for_frontend() {
        let snapshot = ProcessSnapshot::new(
            7,
            vec![ProcessEntry {
                key: crate::model::ProcessKey {
                    pid: 42,
                    start_sec: 123,
                    start_usec: Some(456),
                },
                name: "runner".into(),
                cpu_percent: Some(12.5),
                rss_bytes: Some(4096),
                status: crate::model::ProcessState::Running,
                parent_pid: Some(1),
                cwd: crate::model::PathEvidence::available("/tmp".into()),
                executable: crate::model::PathEvidence::available("/bin/runner".into()),
                context_display: Some("/tmp".into()),
                context_kind: Some("cwd".into()),
            }],
        );
        let value = serde_json::to_value(snapshot).expect("snapshot should serialize");
        assert_eq!(value["entries"][0]["cpuPercent"], 12.5);
        assert_eq!(value["entries"][0]["rssBytes"], 4096);
        assert_eq!(value["entries"][0]["key"]["startUsec"], 456);
    }
}
