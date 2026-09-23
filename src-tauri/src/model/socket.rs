use serde::{Deserialize, Serialize};

/// Socket record as returned by the OS, before a single owning PID is chosen.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawSocket {
    pub protocol: Protocol,
    pub state: SocketState,
    pub local_address: String,
    pub local_port: u16,
    pub remote_address: Option<String>,
    pub remote_port: Option<u16>,
    pub associated_pids: Vec<u32>,
}

/// One raw socket paired with the PID selected for process lookup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PidAssociatedSocket {
    pub socket: RawSocket,
    pub pid: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SocketEntry {
    pub pid: Option<u32>,
    pub process_name: Option<String>,
    pub protocol: Protocol,
    pub state: SocketState,
    pub local_address: String,
    pub local_port: u16,
    pub remote_address: Option<String>,
    pub remote_port: Option<u16>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Protocol {
    Tcp,
    Udp,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SocketState {
    Closed,
    Listen,
    SynSent,
    SynReceived,
    Established,
    FinWait1,
    FinWait2,
    CloseWait,
    Closing,
    LastAck,
    TimeWait,
    DeleteTcb,
    Unknown,
    /// UDP has no TCP state.
    None,
}
