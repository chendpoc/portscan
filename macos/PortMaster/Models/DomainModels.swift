import Foundation

enum ProtocolKind: String, Codable, CaseIterable {
    case tcp
    case udp
}

enum SocketStateKind: String, Codable, CaseIterable {
    case closed, listen, synSent = "syn_sent", synReceived = "syn_received"
    case established, finWait1 = "fin_wait1", finWait2 = "fin_wait2"
    case closeWait = "close_wait", closing, lastAck = "last_ack"
    case timeWait = "time_wait", deleteTcb = "delete_tcb", unknown, none
}

enum EvidenceState: String, Codable {
    case available, restricted, unavailable
}

struct PathEvidence: Equatable, Codable {
    var state: EvidenceState
    var path: String?
    var message: String?

    static func available(_ path: String) -> PathEvidence {
        PathEvidence(state: .available, path: path, message: nil)
    }

    static func restricted(_ message: String) -> PathEvidence {
        PathEvidence(state: .restricted, path: nil, message: message)
    }

    static func unavailable(_ message: String) -> PathEvidence {
        PathEvidence(state: .unavailable, path: nil, message: message)
    }
}

struct ProcessKey: Hashable, Codable, Identifiable {
    var pid: UInt32
    var startSec: UInt64
    var startUsec: UInt64?

    var id: String { ProcessKeyFormatting.id(for: self) }
}

enum ProcessStateKind: String, Codable {
    case running, sleeping, stopped, zombie, unknown
}

struct ProcessEntry: Identifiable, Equatable {
    var key: ProcessKey
    var name: String
    var cpuPercent: Double?
    var rssBytes: UInt64?
    var status: ProcessStateKind
    var parentPid: UInt32?
    var cwd: PathEvidence
    var executable: PathEvidence
    var contextDisplay: String?
    var contextKind: String?

    var id: String { key.id }
}

struct SocketEntry: Identifiable, Equatable {
    var pid: UInt32?
    var processKey: ProcessKey?
    var processName: String?
    var protocolKind: ProtocolKind
    var state: SocketStateKind
    var localAddress: String
    var localPort: UInt16
    var remoteAddress: String?
    var remotePort: UInt16?

    var id: String {
        [
            String(pid ?? 0),
            protocolKind.rawValue,
            localAddress,
            String(localPort),
            remoteAddress ?? "",
            String(remotePort ?? 0),
            state.rawValue,
        ].joined(separator: "|")
    }
}

struct InterfaceInfo: Equatable {
    var name: String
    var receivedBytes: UInt64
    var transmittedBytes: UInt64
}

struct ProcessSnapshot: Equatable {
    var generation: UInt64
    var capturedAt: Date
    var entries: [ProcessEntry]
}

struct SocketSnapshot: Equatable {
    var generation: UInt64
    var capturedAt: Date
    var sockets: [SocketEntry]
    var interfaces: [InterfaceInfo]
}

struct MonitorState: Equatable {
    var processes: ProcessSnapshot?
    var sockets: SocketSnapshot?
    var processError: String?
    var socketError: String?
    var processErrorGeneration: UInt64?
    var socketErrorGeneration: UInt64?
}

struct RefreshSettings: Equatable {
    var intervalMs: UInt64 = 2000
    var paused: Bool = false
    var includeUdp: Bool = true
    var includeIpv6: Bool = true
}

enum PrimaryView: String, CaseIterable {
    case processes, ports
}

enum ProcessSort: String, CaseIterable {
    case cpu, memory, pid
}

enum ProcessFilter: String, CaseIterable {
    case all, running, withListeners = "with_listeners"
}

enum PortsFilter: String, CaseIterable {
    case listeners, all
}

struct AncestryNode: Equatable, Codable {
    var key: ProcessKey
    var name: String
    var relationshipVerified: Bool
}

struct ProcessDetail: Equatable {
    var key: ProcessKey
    var command: [String]?
    var exe: String?
    var cwd: PathEvidence
    var executable: PathEvidence
    var appBundle: String?
    var collectedAt: Date
    var verifiedAt: Date
    var ancestry: [AncestryNode]
    var ancestryIncomplete: Bool
    var startTimeIso: String?
}

enum RenderStatus: Equatable {
    case loading, live, paused, error, stale
}
