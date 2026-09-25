import Foundation

enum SocketCollector {
    private static let capacity = 16_384

    static func collect(
        includeUDP: Bool,
        includeIPv6: Bool,
        processes: [ProcessEntry],
    ) throws -> [SocketEntry] {
        var buffer = [pm_socket_record](repeating: pm_socket_record(), count: capacity)
        let count = buffer.withUnsafeMutableBufferPointer { pointer in
            pm_collect_sockets(
                pointer.baseAddress,
                Int32(capacity),
                includeUDP ? 1 : 0,
                includeIPv6 ? 1 : 0,
            )
        }
        guard count >= 0 else {
            throw CollectorError.socket("Unable to read local sockets")
        }
        let total = Int(count)

        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.key.pid, $0) })
        var raw: [RawSocket] = []
        raw.reserveCapacity(total)
        for index in 0..<total {
            let record = buffer[index]
            let protocolKind: ProtocolKind = record.`protocol` == 6 ? .tcp : .udp
            let state = mapState(protocolKind: protocolKind, tcpState: record.tcp_state)
            raw.append(
                RawSocket(
                    pid: record.pid,
                    protocolKind: protocolKind,
                    state: state,
                    localAddress: cString(record.local_address),
                    localPort: record.local_port,
                    remoteAddress: optionalAddress(cString(record.remote_address)),
                    remotePort: record.remote_port == 0 ? nil : record.remote_port,
                ),
            )
        }
        return normalize(raw: raw, processesByPID: byPID)
    }

    private static func mapState(protocolKind: ProtocolKind, tcpState: UInt8) -> SocketStateKind {
        if protocolKind == .udp { return .none }
        switch tcpState {
        case 0: return .closed
        case 1: return .listen
        case 2: return .synSent
        case 3: return .synReceived
        case 4: return .established
        case 5: return .closeWait
        case 6: return .finWait1
        case 7: return .closing
        case 8: return .lastAck
        case 9: return .finWait2
        case 10: return .timeWait
        default: return .unknown
        }
    }
}

private struct RawSocket {
    var pid: UInt32
    var protocolKind: ProtocolKind
    var state: SocketStateKind
    var localAddress: String
    var localPort: UInt16
    var remoteAddress: String?
    var remotePort: UInt16?
}

private func normalize(raw: [RawSocket], processesByPID: [UInt32: ProcessEntry]) -> [SocketEntry] {
    raw.map { item in
        let process = processesByPID[item.pid]
        let (remoteAddress, remotePort) = remoteEndpoint(item)
        return SocketEntry(
            pid: item.pid,
            processKey: process?.key,
            processName: process?.name,
            protocolKind: item.protocolKind,
            state: item.state,
            localAddress: item.localAddress,
            localPort: item.localPort,
            remoteAddress: remoteAddress,
            remotePort: remotePort,
        )
    }
}

private func remoteEndpoint(_ socket: RawSocket) -> (String?, UInt16?) {
    if socket.protocolKind == .udp || socket.state == .listen { return (nil, nil) }
    if let address = socket.remoteAddress, socket.remotePort == 0, isUnspecified(address) {
        return (nil, nil)
    }
    return (socket.remoteAddress, socket.remotePort)
}

private func isUnspecified(_ address: String) -> Bool {
    address == "0.0.0.0" || address == "::"
}

private func cString<T>(_ buffer: T) -> String {
    var copy = buffer
    return withUnsafePointer(to: &copy) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
    }
}

private func optionalAddress(_ value: String) -> String? {
    value.isEmpty ? nil : value
}
