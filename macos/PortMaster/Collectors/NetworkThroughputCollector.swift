import Darwin
import Foundation
import SystemConfiguration

/// 网络吞吐采集：getifaddrs 接口字节计数差值 ÷ 实际间隔 = B/s。
/// 按接口分别记录，跳过 loopback 与未启用接口。
final class NetworkThroughputCollector {
    struct Throughput: Equatable {
        var rxBytesPerSec: Double
        var txBytesPerSec: Double
    }

    private struct Counter {
        var rx: UInt64
        var tx: UInt64
        var capturedAt: Date
    }

    private var previous: [String: Counter] = [:]

    /// 返回各接口当前速率。首个样本（无前值）返回空字典。
    func sample() -> [String: Throughput] {
        let now = Date()
        let counters = readCounters(at: now)
        var result: [String: Throughput] = [:]
        for (name, counter) in counters {
            guard let before = previous[name] else { continue }
            let elapsed = now.timeIntervalSince(before.capturedAt)
            guard elapsed > 0 else { continue }
            let rx = Double(counter.rx &- before.rx) / elapsed
            let tx = Double(counter.tx &- before.tx) / elapsed
            result[name] = Throughput(rxBytesPerSec: max(0, rx), txBytesPerSec: max(0, tx))
        }
        previous = counters
        return result
    }

    private func readCounters(at now: Date) -> [String: Counter] {
        var result: [String: Counter] = [:]
        var addrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrsPointer) == 0, let first = addrsPointer else { return [:] }
        defer { freeifaddrs(addrsPointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = current?.pointee {
            defer { current = ifa.ifa_next }
            guard let address = ifa.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK else { continue }
            let name = String(cString: ifa.ifa_name)
            guard !name.hasPrefix("lo"), ifa.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            guard let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
            let rx = UInt64(data.ifi_ibytes)
            let tx = UInt64(data.ifi_obytes)
            if let existing = result[name] {
                result[name] = Counter(rx: existing.rx + rx, tx: existing.tx + tx, capturedAt: now)
            } else {
                result[name] = Counter(rx: rx, tx: tx, capturedAt: now)
            }
        }
        return result
    }

    /// BSD 接口名 → 本地化显示名（如 en0 → Wi-Fi），经 SystemConfiguration。
    static func displayNames() -> [String: String] {
        var map: [String: String] = [:]
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return map }
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            map[bsd] = display.map { "\(bsd) (\($0))" } ?? bsd
        }
        return map
    }
}
