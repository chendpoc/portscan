import XCTest
@testable import PortMaster

/// 磁盘吞吐采集冒烟：IOKit 块存储计数器应可读，第二次采样给出非负速率。
final class DiskThroughputTests: XCTestCase {
    func testDiskCountersReadable() {
        let collector = DiskThroughputCollector()
        XCTAssertNil(collector.sample(), "首个样本无前值，应为 nil")
        Thread.sleep(forTimeInterval: 0.3)
        guard let second = collector.sample() else {
            XCTFail("第二次采样仍无结果——IOBlockStorageDriver Statistics 读取失败？")
            return
        }
        XCTAssertGreaterThanOrEqual(second.readBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(second.writeBytesPerSec, 0)
    }
}
