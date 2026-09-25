import XCTest
@testable import PortMaster

/// Inspector 观察采样管线：选中进程后必须持续积累含 RSS 的样本（曾出现 RSS 图表无数据）。
final class ObservedRecordingTests: XCTestCase {
    @MainActor
    func testObservedSamplesContainRSS() async throws {
        let model = MonitorViewModel()
        model.start()
        defer { model.stop() }
        // 等待首轮进程数据
        try await Task.sleep(nanoseconds: 2_500_000_000)
        guard let selfEntry = (model.monitor.processes?.entries ?? []).first(where: {
            $0.key.pid == UInt32(getpid())
        }) else {
            XCTFail("清单中找不到当前进程")
            return
        }
        model.selectProcess(selfEntry)
        // 等 ≥2 个刷新周期，样本应开始积累
        try await Task.sleep(nanoseconds: 5_000_000_000)

        let id = ProcessKeyFormatting.id(for: selfEntry.key)
        let record = model.observed[id]
        XCTAssertNotNil(record, "选中后未建立观察记录")
        XCTAssertGreaterThan(record?.samples.count ?? 0, 1, "观察样本未积累（图表需要 >1 个样本）")
        let rssValues = record?.samples.compactMap(\.rss) ?? []
        XCTAssertFalse(rssValues.isEmpty, "观察样本中 RSS 全部为空——RSS 图表将无数据")
    }
}
