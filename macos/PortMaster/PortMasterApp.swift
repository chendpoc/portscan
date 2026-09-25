import SwiftUI

@main
struct PortMasterApp: App {
    @State private var model = MonitorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
//        .commands {
//            CommandGroup(replacing: .newItem) {}
//            CommandGroup(after: .newItem) {
//                Button("端口搜索") {
//                    NotificationCenter.default.post(name: .focusPortSearch, object: nil)
//                }
//                .keyboardShortcut("k", modifiers: .command)
//            }
//        }
    }
}
