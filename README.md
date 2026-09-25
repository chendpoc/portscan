# PortMaster

查看这台 Mac 上已经打开的套接字与占用端口的进程。采集走 Darwin `libproc` 与本机套接字扫描，不会去连别的主机。

进程与套接字分开刷新；某一侧失败时保留上一份成功数据并标记为过期。界面为 SwiftUI macOS 应用（不启用 App Sandbox，以便读取其他进程信息）。

## 开发

在 Xcode 中打开 `macos/PortMaster.xcodeproj`，选择 **PortMaster** scheme 运行。

命令行构建与测试：

```bash
xcodebuild -project macos/PortMaster.xcodeproj -scheme PortMaster -configuration Debug build test
```

Release 构建产物位于 DerivedData；也可在 Xcode 中 **Product → Archive**。

## 要求

- macOS 14 或更高
- Xcode 15 或更高
