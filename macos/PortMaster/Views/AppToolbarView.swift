import SwiftUI

struct AppToolbarView: View {
    @Bindable var model: MonitorViewModel

    var body: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $model.view) {
                Text("Processes").tag(PrimaryView.processes)
                Text("Ports").tag(PrimaryView.ports)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            TextField("Search process or port", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Spacer()

            Button {
                model.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.refreshing)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
}
