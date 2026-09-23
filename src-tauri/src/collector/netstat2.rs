use netstat2::{get_sockets_info, AddressFamilyFlags, ProtocolFlags, ProtocolSocketInfo, TcpState};

use crate::error::CollectorError;
use crate::model::{Protocol, RawSocket, SocketState};

pub struct Netstat2Collector {
    include_udp: bool,
    include_ipv6: bool,
}

impl Default for Netstat2Collector {
    fn default() -> Self {
        Self {
            include_udp: true,
            include_ipv6: true,
        }
    }
}

impl Netstat2Collector {
    pub fn set_filter(&mut self, include_udp: bool, include_ipv6: bool) {
        self.include_udp = include_udp;
        self.include_ipv6 = include_ipv6;
    }

    pub fn collect(&self) -> Result<Vec<RawSocket>, CollectorError> {
        let families = if self.include_ipv6 {
            AddressFamilyFlags::IPV4 | AddressFamilyFlags::IPV6
        } else {
            AddressFamilyFlags::IPV4
        };
        let protocols = if self.include_udp {
            ProtocolFlags::TCP | ProtocolFlags::UDP
        } else {
            ProtocolFlags::TCP
        };

        let sockets = get_sockets_info(families, protocols)
            .map_err(|err| CollectorError::Netstat(err.to_string()))?;

        Ok(sockets.into_iter().map(raw_from_info).collect())
    }
}

fn raw_from_info(info: netstat2::SocketInfo) -> RawSocket {
    let associated_pids = info.associated_pids;
    match info.protocol_socket_info {
        ProtocolSocketInfo::Tcp(tcp) => RawSocket {
            protocol: Protocol::Tcp,
            state: map_tcp_state(tcp.state),
            local_address: tcp.local_addr.to_string(),
            local_port: tcp.local_port,
            remote_address: Some(tcp.remote_addr.to_string()),
            remote_port: Some(tcp.remote_port),
            associated_pids,
        },
        ProtocolSocketInfo::Udp(udp) => RawSocket {
            protocol: Protocol::Udp,
            state: SocketState::None,
            local_address: udp.local_addr.to_string(),
            local_port: udp.local_port,
            remote_address: None,
            remote_port: None,
            associated_pids,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collects_local_sockets() {
        let sockets = Netstat2Collector::default()
            .collect()
            .expect("netstat2 should read sockets on this machine");
        let _ = sockets;
    }
}

fn map_tcp_state(state: TcpState) -> SocketState {
    match state {
        TcpState::Closed => SocketState::Closed,
        TcpState::Listen => SocketState::Listen,
        TcpState::SynSent => SocketState::SynSent,
        TcpState::SynReceived => SocketState::SynReceived,
        TcpState::Established => SocketState::Established,
        TcpState::FinWait1 => SocketState::FinWait1,
        TcpState::FinWait2 => SocketState::FinWait2,
        TcpState::CloseWait => SocketState::CloseWait,
        TcpState::Closing => SocketState::Closing,
        TcpState::LastAck => SocketState::LastAck,
        TcpState::TimeWait => SocketState::TimeWait,
        TcpState::DeleteTcb => SocketState::DeleteTcb,
        TcpState::Unknown => SocketState::Unknown,
    }
}
