import Foundation

enum MonitorLogic {
    static func staleThresholdMs(intervalMs: UInt64) -> UInt64 {
        max(intervalMs * 3, 5000)
    }

    static func isSnapshotStale(
        capturedAt: Date?,
        intervalMs: UInt64,
        sourceFailed: Bool,
        now: Date,
    ) -> Bool {
        if sourceFailed { return true }
        guard let capturedAt else { return true }
        let ageMs = UInt64(max(0, now.timeIntervalSince(capturedAt) * 1000))
        return ageMs > staleThresholdMs(intervalMs: intervalMs)
    }

    static func parseNumericQuery(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }
        return Int(trimmed)
    }

    static func matchesProcessSearch(
        _ entry: ProcessEntry,
        query: String,
        listenPorts: some Sequence<Int>,
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let numeric = parseNumericQuery(trimmed) {
            if Int(entry.key.pid) == numeric { return true }
            return listenPorts.contains(numeric)
        }
        let needle = trimmed.lowercased()
        let haystacks = [
            entry.name,
            entry.contextDisplay ?? "",
            entry.cwd.path ?? "",
            entry.executable.path ?? "",
        ]
        return haystacks.contains { $0.lowercased().contains(needle) }
    }

    static func matchesPortSearch(
        _ entry: SocketEntry,
        query: String,
        contextPath: String,
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let numeric = parseNumericQuery(trimmed) {
            if Int(entry.localPort) == numeric { return true }
            if let pid = entry.pid, Int(pid) == numeric { return true }
            return false
        }
        let needle = trimmed.lowercased()
        let haystacks = [
            entry.processName ?? "",
            entry.localAddress,
            String(entry.localPort),
            contextPath,
        ]
        return haystacks.contains { $0.lowercased().contains(needle) }
    }

    static func compareProcess(
        _ a: ProcessEntry,
        _ b: ProcessEntry,
        by: ProcessSort,
        descending: Bool,
    ) -> Bool {
        let sign: (ComparisonResult) -> ComparisonResult = { descending ? $0.reversed() : $0 }
        if by == .name {
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame {
                return sign(order) == .orderedAscending
            }
            return a.key.pid < b.key.pid
        }
        if by == .pid {
            return sign(a.key.pid.compare(b.key.pid)) == .orderedAscending
        }
        let metric: (ProcessEntry) -> Double?
        switch by {
        case .cpu: metric = { $0.cpuPercent }
        case .memory: metric = { $0.rssBytes.map(Double.init) }
        case .time: metric = { $0.cpuTimeSeconds }
        case .threads: metric = { $0.threadCount.map(Double.init) }
        case .pid, .name: return false // 已在上面处理
        }
        let left = metric(a)
        let right = metric(b)
        if left == nil, right != nil { return false }
        if left != nil, right == nil { return true }
        let delta = (left ?? 0) - (right ?? 0)
        if delta == 0 {
            return sign(a.key.pid.compare(b.key.pid)) == .orderedAscending
        }
        return sign(delta.compare(to: 0)) == .orderedAscending
    }

    /// 相邻样本间隔超过 1.5×采样周期视为时间缺口（暂停/恢复后断开折线，不回填）。
    static func hasSamplingGap(previous: Date, current: Date, tickSeconds: TimeInterval) -> Bool {
        current.timeIntervalSince(previous) > tickSeconds * 1.5
    }

    /// 去除完全相同的套接字行（SO_REUSEPORT 下同进程、同协议、同地址、同端口、
    /// 同远端、同状态的重复绑定）；端口/地址/协议/进程/远端任一不同的条目保留。
    static func dedupeSockets(_ sockets: [SocketEntry]) -> [SocketEntry] {
        var seen: Set<String> = []
        return sockets.filter { seen.insert($0.id).inserted }
    }

    /// 首轮加载中 ⇔ 从未成功加载且未报错。
    /// 回归防护：曾把「数据还没到」误显示为「没有匹配」空态——三态必须区分。
    static func isInitialLoading(snapshotLoaded: Bool, error: String?) -> Bool {
        !snapshotLoaded && error == nil
    }

    /// Inspector 迷你趋势图 Y 轴上限（字节或百分比等同一量纲的 v 值）。
    /// 必须用 Swift.max：在 ViewBuilder 里写 `max(1, …)` 会与 `.max()` 链式调用歧义，曾把 RSS 的 yMax 算成 1。
    static func trendChartYMax(values: [Double], headroom: Double = 1.2) -> Double {
        let peak = values.max() ?? 0
        return Swift.max(1, peak * headroom)
    }

    /// 稳定量程：取 nice(峰值×1.15)，仅当新量程超出当前或收缩到 45% 以下时调整，
    /// 避免吞吐图纵轴频繁跳动。
    static func stableScale(current: Double?, maxValue: Double) -> Double {
        func nice(_ value: Double) -> Double {
            let power = pow(10, floor(log10(max(value, 1))))
            for multiplier in [1.0, 2, 5, 10] where value <= multiplier * power {
                return multiplier * power
            }
            return 10 * power
        }
        let want = nice(maxValue * 1.15)
        guard let current, current > 0 else { return want }
        if want > current || want < current * 0.45 { return want }
        return current
    }

    static func listenerPortFilter(_ entry: SocketEntry) -> Bool {
        if entry.protocolKind == .tcp { return entry.state == .listen }
        return entry.protocolKind == .udp && entry.state == .none
    }

    static func listenPortsByProcess(_ sockets: [SocketEntry]) -> [String: Set<Int>] {
        var map: [String: Set<Int>] = [:]
        for entry in sockets {
            guard let key = entry.processKey else { continue }
            let isListener = entry.state == .listen || (entry.protocolKind == .udp && entry.state == .none)
            guard isListener else { continue }
            let id = ProcessKeyFormatting.id(for: key)
            var set = map[id] ?? []
            set.insert(Int(entry.localPort))
            map[id] = set
        }
        return map
    }

    static func filterProcesses(
        _ entries: [ProcessEntry],
        query: String,
        listenPortSets: [String: Set<Int>],
        processFilter: ProcessFilter,
        sort: ProcessSort,
        descending: Bool,
    ) -> [ProcessEntry] {
        entries.filter { entry in
            if processFilter == .running, entry.status != .running { return false }
            if processFilter == .withListeners {
                let ports = listenPortSets[entry.id]
                guard let ports, !ports.isEmpty else { return false }
            }
            let ports = listenPortSets[entry.id] ?? []
            return matchesProcessSearch(entry, query: query, listenPorts: ports)
        }
        .sorted { compareProcess($0, $1, by: sort, descending: descending) }
    }

    static func filterPorts(
        _ sockets: [SocketEntry],
        query: String,
        contextPaths: [String: String],
        portsFilter: PortsFilter,
        protocolFilter: ProtocolKind?,
        connectionState: SocketStateKind?,
        portScope: ProcessKey?,
    ) -> [SocketEntry] {
        sockets.filter { entry in
            if portsFilter == .listeners, !listenerPortFilter(entry) { return false }
            if let protocolFilter, entry.protocolKind != protocolFilter { return false }
            if let connectionState, entry.state != connectionState { return false }
            if let portScope, let key = entry.processKey {
                if ProcessKeyFormatting.id(for: key) != ProcessKeyFormatting.id(for: portScope) {
                    return false
                }
            } else if portScope != nil {
                return false
            }
            let context = entry.processKey.flatMap { contextPaths[ProcessKeyFormatting.id(for: $0)] } ?? ""
            return matchesPortSearch(entry, query: query, contextPath: context)
        }
        .sorted {
            if $0.localPort != $1.localPort { return $0.localPort < $1.localPort }
            return $0.localAddress.localizedStandardCompare($1.localAddress) == .orderedAscending
        }
    }
}

private extension ComparisonResult {
    func reversed() -> ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

private extension Double {
    func compare(to other: Double) -> ComparisonResult {
        if self < other { return .orderedAscending }
        if self > other { return .orderedDescending }
        return .orderedSame
    }
}

private extension UInt32 {
    func compare(_ other: UInt32) -> ComparisonResult {
        if self < other { return .orderedAscending }
        if self > other { return .orderedDescending }
        return .orderedSame
    }
}
