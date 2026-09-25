import Foundation

/// 启动序列纯逻辑（可单测）。视图层只做绑定，判定全部在这里。
enum LaunchLogic {
    /// 品牌首启仅当：未被测试/诊断关闭，且用户从未看过。
    static func shouldShowBrandLaunch(showsBrandLaunch: Bool, didLaunchBrand: Bool) -> Bool {
        showsBrandLaunch && !didLaunchBrand
    }
}
