import Foundation
import IOKit

/// 磁盘吞吐采集：IOBlockStorageDriver 注册表 Statistics 累计字节差值 ÷ 实际间隔 = B/s。
/// 与 iostat 同源，无需特权；汇总全部块存储驱动（整机口径）。
final class DiskThroughputCollector {
    struct Throughput: Equatable {
        var readBytesPerSec: Double
        var writeBytesPerSec: Double
    }

    private var previous: (read: UInt64, write: UInt64, capturedAt: Date)?

    /// 首个样本（无前值）返回 nil。
    func sample() -> Throughput? {
        let counters = readCounters()
        let now = Date()
        defer { previous = (counters.read, counters.write, now) }
        guard let before = previous else { return nil }
        let elapsed = now.timeIntervalSince(before.capturedAt)
        guard elapsed > 0 else { return nil }
        return Throughput(
            readBytesPerSec: max(0, Double(counters.read &- before.read) / elapsed),
            writeBytesPerSec: max(0, Double(counters.write &- before.write) / elapsed),
        )
    }

    private func readCounters() -> (read: UInt64, write: UInt64) {
        var read: UInt64 = 0
        var write: UInt64 = 0
        var mainPort = mach_port_t()
        guard IOMainPort(0, &mainPort) == KERN_SUCCESS else { return (0, 0) }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            mainPort,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator,
        ) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Written)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
        }
        return (read, write)
    }
}
