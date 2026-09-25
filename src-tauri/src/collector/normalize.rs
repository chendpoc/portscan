use std::collections::HashMap;

use crate::model::{PidAssociatedSocket, ProcessEntry, Protocol, SocketEntry, SocketState};

pub fn normalize(
    associated: Vec<PidAssociatedSocket>,
    processes: &HashMap<u32, ProcessEntry>,
) -> Vec<SocketEntry> {
    associated
        .into_iter()
        .map(|item| {
            let process = item.pid.and_then(|pid| processes.get(&pid));
            let process_name = process
                .map(|process| process.name.clone())
                .filter(|name| !name.is_empty());
            let (remote_address, remote_port) = remote_endpoint(&item.socket);
            SocketEntry {
                pid: item.pid,
                process_key: process.map(|process| process.key),
                process_name,
                protocol: item.socket.protocol,
                state: item.socket.state,
                local_address: item.socket.local_address,
                local_port: item.socket.local_port,
                remote_address,
                remote_port,
            }
        })
        .collect()
}

fn remote_endpoint(socket: &crate::model::RawSocket) -> (Option<String>, Option<u16>) {
    if socket.protocol == Protocol::Udp || socket.state == SocketState::Listen {
        return (None, None);
    }
    match (&socket.remote_address, socket.remote_port) {
        (Some(address), Some(0)) if is_unspecified(address) => (None, None),
        (address, port) => (address.clone(), port),
    }
}

fn is_unspecified(address: &str) -> bool {
    matches!(address, "0.0.0.0" | "::")
}
