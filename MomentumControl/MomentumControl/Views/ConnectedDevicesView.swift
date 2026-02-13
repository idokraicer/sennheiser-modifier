import SwiftUI

struct ConnectedDevicesView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paired Devices (\(viewModel.state.pairedDeviceCount))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.state.pairedDevices.isEmpty && viewModel.state.pairedDeviceCount > 0 {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.state.pairedDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.callout)
                            Text(device.displayConnectionState)
                                .font(.caption2)
                                .foregroundStyle(device.isConnected ? .green : .secondary)
                        }

                        Spacer()

                        if device.isConnected {
                            Button("Disconnect") {
                                viewModel.disconnectPairedDevice(index: device.index)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Connect") {
                                viewModel.connectPairedDevice(index: device.index)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
