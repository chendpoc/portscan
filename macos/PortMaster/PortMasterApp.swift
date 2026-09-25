import SwiftUI

@main
struct PortMasterApp: App {
    @State private var model = MonitorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 760, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
