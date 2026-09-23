use std::collections::HashMap;

use sysinfo::{Pid, ProcessesToUpdate, System};

use crate::model::{PidAssociatedSocket, ProcessInfo};

pub struct ProcessInfoCollector {
    system: System,
}

impl ProcessInfoCollector {
    pub fn new() -> Self {
        Self {
            system: System::new(),
        }
    }

    pub fn lookup(&mut self, associated: &[PidAssociatedSocket]) -> HashMap<u32, ProcessInfo> {
        let mut pids = Vec::new();
        for socket in associated {
            if let Some(pid) = socket.pid {
                if !pids.contains(&pid) {
                    pids.push(pid);
                }
            }
        }
        if pids.is_empty() {
            return HashMap::new();
        }

        let sys_pids: Vec<Pid> = pids.iter().copied().map(Pid::from_u32).collect();
        let _updated = self
            .system
            .refresh_processes(ProcessesToUpdate::Some(&sys_pids), true);

        let mut found = HashMap::new();
        for pid in pids {
            let Some(process) = self.system.process(Pid::from_u32(pid)) else {
                continue;
            };
            let name = process.name().to_string_lossy().into_owned();
            let exe = process
                .exe()
                .map(|path| path.to_string_lossy().into_owned())
                .filter(|path| !path.is_empty());
            found.insert(
                pid,
                ProcessInfo {
                    pid,
                    name,
                    exe,
                    memory_bytes: process.memory(),
                },
            );
        }
        found
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn looks_up_the_current_process() {
        let mut collector = ProcessInfoCollector::new();
        let pid = std::process::id();
        let associated = vec![PidAssociatedSocket {
            socket: crate::model::RawSocket {
                protocol: crate::model::Protocol::Tcp,
                state: crate::model::SocketState::Established,
                local_address: "127.0.0.1".into(),
                local_port: 1,
                remote_address: None,
                remote_port: None,
                associated_pids: vec![pid],
            },
            pid: Some(pid),
        }];
        let found = collector.lookup(&associated);
        let process = found.get(&pid).expect("current process should be visible");
        assert!(!process.name.is_empty());
    }
}
