use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::interface::InterfaceInfo;
use super::socket::{SocketEntry, SocketState};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SocketSnapshot {
    pub captured_at: DateTime<Utc>,
    pub sockets: Vec<SocketEntry>,
    pub interfaces: Vec<InterfaceInfo>,
}

impl SocketSnapshot {
    pub fn new(mut sockets: Vec<SocketEntry>, mut interfaces: Vec<InterfaceInfo>) -> Self {
        sockets.sort_by(|left, right| {
            state_rank(left.state)
                .cmp(&state_rank(right.state))
                .then(left.local_port.cmp(&right.local_port))
                .then(left.process_name.cmp(&right.process_name))
                .then(left.pid.cmp(&right.pid))
        });
        interfaces.sort_by(|left, right| left.name.cmp(&right.name));
        Self {
            captured_at: Utc::now(),
            sockets,
            interfaces,
        }
    }

    pub fn empty() -> Self {
        Self {
            captured_at: Utc::now(),
            sockets: Vec::new(),
            interfaces: Vec::new(),
        }
    }
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
            vec![
                entry(SocketState::Established, 10),
                entry(SocketState::Listen, 80),
            ],
            vec![],
        );
        assert_eq!(snapshot.sockets[0].state, SocketState::Listen);
        assert_eq!(snapshot.sockets[1].state, SocketState::Established);
    }
}
