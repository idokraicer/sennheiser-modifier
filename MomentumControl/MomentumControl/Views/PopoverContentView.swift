import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.connectionStatus.isConnected {
                ScrollView {
                    VStack(spacing: 16) {
                        DeviceHeaderView(state: viewModel.state)
                        Divider()
                        ANCControlView(viewModel: viewModel)
                        Divider()
                        QuickTogglesView(viewModel: viewModel)
                        Divider()
                        ConnectedDevicesView(viewModel: viewModel)
                        Divider()
                        SettingsView(viewModel: viewModel)
                    }
                    .padding()
                }
            } else {
                DeviceScannerView(viewModel: viewModel)
                    .padding()
            }

            Divider()

            HStack {
                if viewModel.state.connectionStatus.isConnected {
                    Button("Disconnect") {
                        viewModel.disconnect()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
