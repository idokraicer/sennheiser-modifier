import SwiftUI

struct ConnectedDevicesView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paired Devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(viewModel.state.pairedDeviceCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            if viewModel.state.pairedDevices.isEmpty && viewModel.state.pairedDeviceCount > 0 {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.state.pairedDevices) { device in
                    let isConnecting = viewModel.state.connectingDevices.contains(device.index)
                    let isDisconnecting = viewModel.state.disconnectingDevices.contains(device.index)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(dotColor(connected: device.isConnected, connecting: isConnecting, disconnecting: isDisconnecting))
                            .frame(width: 6, height: 6)

                        Text(device.name)
                            .font(.callout)
                            .lineLimit(1)

                        Spacer()

                        if isConnecting {
                            Text("Connecting…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isDisconnecting {
                            Text("Disconnecting…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if device.isConnected {
                            Button("Disconnect") {
                                viewModel.disconnectPairedDevice(index: device.index)
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        } else {
                            Button("Connect") {
                                viewModel.connectPairedDevice(index: device.index)
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dotColor(connected: Bool, connecting: Bool, disconnecting: Bool) -> Color {
        if connecting || disconnecting { return .orange }
        if connected { return .green }
        return Color.secondary.opacity(0.3)
    }
}
