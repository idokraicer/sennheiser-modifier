import SwiftUI

struct ConnectedDevicesView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if viewModel.state.pairedDevices.isEmpty && viewModel.state.pairedDeviceCount > 0 {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(viewModel.state.pairedDevices.enumerated()), id: \.element.id) { idx, device in
                    if idx > 0 {
                        Divider()
                            .opacity(0.3)
                            .padding(.leading, 28)
                    }
                    deviceRow(device: device)
                }
            }
        }
        .padding(.bottom, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        HStack {
            Text("Paired Devices")
                .font(.system(.caption, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(viewModel.state.pairedDeviceCount)")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private func deviceRow(device: PairedDevice) -> some View {
        let isConnecting = viewModel.state.connectingDevices.contains(device.index)
        let isDisconnecting = viewModel.state.disconnectingDevices.contains(device.index)

        HStack(spacing: 10) {
            Circle()
                .fill(dotColor(connected: device.isConnected, connecting: isConnecting, disconnecting: isDisconnecting))
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                }

            Text(device.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            trailingControl(device: device, isConnecting: isConnecting, isDisconnecting: isDisconnecting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func trailingControl(device: PairedDevice, isConnecting: Bool, isDisconnecting: Bool) -> some View {
        if isConnecting {
            statusLabel("Connecting…")
        } else if isDisconnecting {
            statusLabel("Disconnecting…")
        } else if device.isConnected {
            Button("Disconnect") {
                viewModel.disconnectPairedDevice(index: device.index)
            }
            .buttonStyle(SubtleLinkButtonStyle(color: .secondary))
        } else {
            Button("Connect") {
                viewModel.connectPairedDevice(index: device.index)
            }
            .buttonStyle(SubtleLinkButtonStyle(color: .blue))
        }
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private func dotColor(connected: Bool, connecting: Bool, disconnecting: Bool) -> Color {
        if connecting || disconnecting { return .orange }
        if connected { return .green }
        return Color.secondary.opacity(0.4)
    }
}

/// Compact text-only button used for inline row actions like Connect/Disconnect.
private struct SubtleLinkButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}
