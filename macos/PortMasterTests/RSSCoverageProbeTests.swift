import XCTest
@testable import PortMaster

/// 探查：真实清单中 rssBytes 的覆盖率（Inspector RSS 图 y 轴全部 0MB → 样本 RSS 全 nil）。
final class RSSCoverageProbeTests: XCTestCase {
    func testRSSCoverage() throws {
        let collector = ProcessCollector()
        guard case .success(let snapshot) = collector.sample(generation: 1) else {
            XCTFail("采样失败")
            return
        }
        let total = snapshot.entries.count
        let withRSS = snapshot.entries.filter { $0.rssBytes != nil }.count
        let withCPU = snapshot.entries.filter { $0.cpuTimeSeconds != nil }.count
        print("PROBE total=\(total) withRSS=\(withRSS) withCPUTime=\(withCPU)")
        let nilExamples = snapshot.entries.filter { $0.rssBytes == nil }.prefix(10).map(\.name)
        print("PROBE nil-rss examples: \(nilExamples.joined(separator: ", "))")
        XCTAssertGreaterThan(withRSS, 0)
    }
}
