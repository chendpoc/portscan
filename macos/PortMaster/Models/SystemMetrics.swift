import Foundation

/// 单次系统资源采样（CPU / 内存）。样本时间戳为墙钟，暂停时不采样，
/// 恢复后图表自然形成时间缺口。
struct SystemMetricsSample: Equatable {
    var capturedAt: Date
    /// 整机 CPU 使用率 0–100（全部逻辑核心平均）。首个样本无前值时为 nil。
    var cpuTotal: Double?
    /// CPU 分解：用户态（含 nice）/ 系统态占比 0–100。首个样本为 nil。
    var cpuUser: Double? = nil
    var cpuSystem: Double? = nil
    /// 每个逻辑核心的使用率 0–100。
    var cpuPerCore: [Double]
    var coreCount: Int
    /// Load Average（1 / 5 / 15 分钟），getloadavg。
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0
    /// 已使用内存 = (active + wired + compressed) × pageSize。
    var memoryUsed: UInt64
    /// 构成分解：应用（active）/ 联动（wired）/ 已压缩（compressed）。
    var memoryActive: UInt64 = 0
    var memoryWired: UInt64 = 0
    var memoryCompressed: UInt64 = 0
    var memoryTotal: UInt64
    var swapUsed: UInt64
    /// 交换换入/换出速率（次/秒，vm_statistics64 差值）。首个样本无前值时为 nil。
    var swapInRate: Double? = nil
    var swapOutRate: Double? = nil
    /// kern.memorystatus_level：系统报告的可用内存百分比（越低压力越大）。
    var memoryAvailablePercent: Int?
}

/// 单接口网络吞吐样本（B/s）。
struct NetSample: Equatable {
    var t: Date
    var rx: Double
    var tx: Double
}

/// 磁盘吞吐样本（B/s，整机口径）。
struct DiskSample: Equatable {
    var t: Date
    var read: Double
    var write: Double
}

/// Inspector 趋势图：仅从用户选中该进程起记录，不伪造更早历史。
struct ObservedSample: Equatable {
    var t: Date
    var cpu: Double?
    var rss: UInt64?
}

struct ObservedProcess: Equatable {
    var t0: Date
    var samples: [ObservedSample]
}
