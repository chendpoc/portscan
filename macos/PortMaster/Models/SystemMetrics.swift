import Foundation

/// 单次系统资源采样（CPU / 内存）。样本时间戳为墙钟，暂停时不采样，
/// 恢复后图表自然形成时间缺口。
struct SystemMetricsSample: Equatable {
    var capturedAt: Date
    /// 整机 CPU 使用率 0–100（全部逻辑核心平均）。首个样本无前值时为 nil。
    var cpuTotal: Double?
    /// 每个逻辑核心的使用率 0–100。
    var cpuPerCore: [Double]
    var coreCount: Int
    /// 已使用内存 = (active + wired + compressed) × pageSize。
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var swapUsed: UInt64
    /// kern.memorystatus_level：系统报告的可用内存百分比（越低压力越大）。
    var memoryAvailablePercent: Int?
}

enum MemoryPressureKind: String {
    case normal, warning, critical

    init(availablePercent: Int) {
        switch availablePercent {
        case 40...100: self = .normal
        case 15..<40: self = .warning
        default: self = .critical
        }
    }
}

/// 单接口网络吞吐样本（B/s）。
struct NetSample: Equatable {
    var t: Date
    var rx: Double
    var tx: Double
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
