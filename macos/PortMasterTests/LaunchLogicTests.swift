import XCTest
@testable import PortMaster

/// 启动序列纯逻辑契约。
final class LaunchLogicTests: XCTestCase {
    func testBrandLaunchGate() {
        // 首次运行（未看过）→ 显示
        XCTAssertTrue(LaunchLogic.shouldShowBrandLaunch(showsBrandLaunch: true, didLaunchBrand: false))
        // 已看过 → 永不显示
        XCTAssertFalse(LaunchLogic.shouldShowBrandLaunch(showsBrandLaunch: true, didLaunchBrand: true))
        // 测试/诊断关闭 → 不显示（防 UserDefaults 污染）
        XCTAssertFalse(LaunchLogic.shouldShowBrandLaunch(showsBrandLaunch: false, didLaunchBrand: false))
        XCTAssertFalse(LaunchLogic.shouldShowBrandLaunch(showsBrandLaunch: false, didLaunchBrand: true))
    }

    func testInitialLoadingThreeWayState() {
        // 首轮采集中：未加载且无错误 → 骨架屏
        XCTAssertTrue(MonitorLogic.isInitialLoading(snapshotLoaded: false, error: nil))
        // 已有数据 → 正常表格
        XCTAssertFalse(MonitorLogic.isInitialLoading(snapshotLoaded: true, error: nil))
        // 加载失败 → 显示错误而不是骨架屏或空态
        XCTAssertFalse(MonitorLogic.isInitialLoading(snapshotLoaded: false, error: "x"))
        // 有数据且报错（保留上一份）→ 正常表格 + 错误条
        XCTAssertFalse(MonitorLogic.isInitialLoading(snapshotLoaded: true, error: "x"))
    }
}
