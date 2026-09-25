mod interface_info;
mod macos_context;
mod macos_identity;
mod netstat2;
mod normalize;
mod process_info;

use crate::model::{PidAssociatedSocket, RawSocket};

pub use interface_info::InterfaceInfoCollector;
pub use macos_context::verified_cwd_for_terminal;
pub use macos_identity::process_start;
pub use netstat2::Netstat2Collector;
pub use normalize::normalize;
pub use process_info::{process_detail, ProcessInfoCollector};

/// Pick an owning PID for each raw socket.
///
/// netstat2 can report several PIDs for one socket. Each non-zero PID becomes
/// its own record so process lookup does not drop a sharing process. PID 0 is
/// ignored. A socket with no PID is kept, with `pid: None`.
pub fn associate_pids(raw_sockets: Vec<RawSocket>) -> Vec<PidAssociatedSocket> {
    let mut associated = Vec::new();
    for socket in raw_sockets {
        let pids = unique_pids(&socket.associated_pids);
        if pids.is_empty() {
            associated.push(PidAssociatedSocket { socket, pid: None });
            continue;
        }
        for pid in pids {
            associated.push(PidAssociatedSocket {
                socket: socket.clone(),
                pid: Some(pid),
            });
        }
    }
    associated
}

fn unique_pids(pids: &[u32]) -> Vec<u32> {
    let mut unique = Vec::new();
    for pid in pids {
        if *pid != 0 && !unique.contains(pid) {
            unique.push(*pid);
        }
    }
    unique
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        PathEvidence, ProcessEntry, ProcessKey, ProcessState, Protocol, RawSocket, SocketState,
    };
    use std::collections::HashMap;

    fn raw(state: SocketState, remote: Option<(&str, u16)>, pids: Vec<u32>) -> RawSocket {
        RawSocket {
            protocol: if state == SocketState::None {
                Protocol::Udp
            } else {
                Protocol::Tcp
            },
            state,
            local_address: "127.0.0.1".into(),
            local_port: 80,
            remote_address: remote.map(|(address, _)| address.to_string()),
            remote_port: remote.map(|(_, port)| port),
            associated_pids: pids,
        }
    }

    #[test]
    fn fans_out_pids_and_attaches_process_names() {
        let associated = associate_pids(vec![raw(
            SocketState::Established,
            Some(("1.2.3.4", 443)),
            vec![10, 10, 0, 11],
        )]);
        assert_eq!(associated.len(), 2);

        let mut processes = HashMap::new();
        processes.insert(
            10,
            ProcessEntry {
                key: ProcessKey {
                    pid: 10,
                    start_sec: 100,
                    start_usec: Some(1),
                },
                name: "browser".into(),
                cpu_percent: Some(1.5),
                rss_bytes: Some(1),
                status: ProcessState::Running,
                parent_pid: None,
                cwd: PathEvidence::unavailable("test"),
                executable: PathEvidence::unavailable("test"),
                context_display: None,
                context_kind: None,
            },
        );
        let entries = normalize(associated, &processes);
        assert_eq!(entries[0].pid, Some(10));
        assert_eq!(entries[0].process_key, Some(processes[&10].key));
        assert_eq!(entries[0].process_name.as_deref(), Some("browser"));
        assert_eq!(entries[0].remote_address.as_deref(), Some("1.2.3.4"));
        assert_eq!(entries[0].remote_port, Some(443));
        assert_eq!(entries[1].pid, Some(11));
        assert!(entries[1].process_name.is_none());
    }

    #[test]
    fn listen_sockets_drop_the_unspecified_remote() {
        let associated =
            associate_pids(vec![raw(SocketState::Listen, Some(("0.0.0.0", 0)), vec![])]);
        let entries = normalize(associated, &HashMap::new());
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].pid, None);
        assert!(entries[0].remote_address.is_none());
        assert!(entries[0].remote_port.is_none());
    }
}
