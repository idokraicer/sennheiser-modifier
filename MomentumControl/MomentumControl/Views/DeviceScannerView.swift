import SwiftUI

struct DeviceScannerView: View {
    @Bindable var viewModel: HeadphoneViewModel
    @State private var isAutoConnecting = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("MomentumControl")
                .font(.headline)

            Text(viewModel.state.connectionStatus.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if case .error(let msg) = viewModel.state.connectionStatus {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Known Sennheiser devices
            let knownDevices = MACResolver.listSennheiserDevices()
            if !knownDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Known Devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(knownDevices, id: \.address) { device in
                        Button {
                            Task {
                                viewModel.state.deviceName = device.name
                                await viewModel.connect(to: device.address)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "headphones")
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                        .font(.callout)
                                    Text(device.address)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }

            // BLE Scanner
            VStack(spacing: 8) {
                if viewModel.bleScanner.isScanning {
                    ProgressView("Scanning...")
                        .font(.caption)
                } else {
                    Button("Scan for Devices") {
                        viewModel.bleScanner.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                ForEach(viewModel.bleScanner.discoveredDevices) { device in
                    Button {
                        Task {
                            viewModel.bleScanner.stopScan()
                            if let mac = MACResolver.resolve(deviceName: device.name) {
                                viewModel.state.deviceName = device.name
                                await viewModel.connect(to: mac)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.callout)
                                Text("RSSI: \(device.rssi)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Auto-connect
            if !isAutoConnecting && !knownDevices.isEmpty {
                Button("Auto-Connect") {
                    isAutoConnecting = true
                    Task {
                        await viewModel.autoConnect()
                        isAutoConnecting = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .task {
            // Try auto-connect on launch
            await viewModel.autoConnect()
        }
    }
}
