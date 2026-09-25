import Darwin
import Foundation

/// 整机 CPU（host_processor_info）与内存（host_statistics64 + vm.swapusage）采样。
/// 全部为本机 Mach/sysctl 调用，微秒级，可在主线程每秒执行。
final class SystemMetricsCollector {
    private struct CoreTicks {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64
    }

    private var previousTicks: [CoreTicks]?

    func sample() -> SystemMetricsSample {
        let cpu = cpuLoad()
        let memory = memoryStats()
        return SystemMetricsSample(
            capturedAt: Date(),
            cpuTotal: cpu.total,
            cpuPerCore: cpu.perCore,
            coreCount: ProcessInfo.processInfo.processorCount,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            swapUsed: memory.swap,
            memoryAvailablePercent: pressureAvailablePercent(),
        )
    }

    // MARK: - CPU

    private func cpuLoad() -> (total: Double?, perCore: [Double]) {
        var cpuInfo: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &infoCount,
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return (nil, []) }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let strideMax = Int(CPU_STATE_MAX)
        var current: [CoreTicks] = []
        current.reserveCapacity(Int(processorCount))
        for index in 0..<Int(processorCount) {
            let base = index * strideMax
            current.append(
                CoreTicks(
                    user: UInt64(bitPattern: Int64(cpuInfo[base + Int(CPU_STATE_USER)])),
                    system: UInt64(bitPattern: Int64(cpuInfo[base + Int(CPU_STATE_SYSTEM)])),
                    idle: UInt64(bitPattern: Int64(cpuInfo[base + Int(CPU_STATE_IDLE)])),
                    nice: UInt64(bitPattern: Int64(cpuInfo[base + Int(CPU_STATE_NICE)])),
                ),
            )
        }

        guard let previous = previousTicks, previous.count == current.count else {
            previousTicks = current
            return (nil, [])
        }
        previousTicks = current

        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        var usedSum = 0.0
        var totalSum = 0.0
        for (now, before) in zip(current, previous) {
            let dUser = Double(now.user &- before.user)
            let dSystem = Double(now.system &- before.system)
            let dIdle = Double(now.idle &- before.idle)
            let dNice = Double(now.nice &- before.nice)
            let total = dUser + dSystem + dIdle + dNice
            let used = dUser + dSystem + dNice
            perCore.append(total > 0 ? min(100, max(0, used / total * 100)) : 0)
            usedSum += used
            totalSum += total
        }
        let total = totalSum > 0 ? min(100, max(0, usedSum / totalSum * 100)) : nil
        return (total, perCore)
    }

    // MARK: - 内存

    private func memoryStats() -> (used: UInt64, total: UInt64, swap: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total, swapUsed()) }
        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = min(usedPages * pageSize, total)
        return (used, total, swapUsed())
    }

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        guard sysctl(&mib, 2, &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// kern.memorystatus_level：可用内存百分比。读取失败（权限）时返回 nil，UI 省略该字段。
    private func pressureAvailablePercent() -> Int? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else { return nil }
        return Int(level)
    }
}
