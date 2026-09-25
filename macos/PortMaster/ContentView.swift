import SwiftUI

struct ContentView: View {
    @Bindable var model: MonitorViewModel
    @State private var compact = false

    var body: some View {
        GeometryReader { proxy in
            let narrow = proxy.size.width < 760
            let inspectorOpen = model.selectedKey != nil
            VStack(spacing: 0) {
                AppToolbarView(model: model)
                if let error = model.monitor.processError ?? model.monitor.socketError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                }
                HStack(spacing: 0) {
                    if !(narrow && inspectorOpen) {
                        Group {
                            if model.view == .processes {
                                ProcessTableView(model: model)
                            } else {
                                PortsTableView(model: model)
                            }
                        }
                        .frame(minWidth: 320)
                    }
                    if inspectorOpen {
                        InspectorPanelView(model: model, compact: narrow, onBack: model.closeInspector)
                            .frame(width: narrow ? nil : 336)
                    }
                }
                StatusFooterView(model: model)
            }
            .frame(minWidth: 640, minHeight: 420)
            .onAppear {
                compact = narrow
                model.start()
            }
            .onDisappear { model.stop() }
            .onChange(of: proxy.size.width) { _, width in compact = width < 760 }
        }
    }
}
