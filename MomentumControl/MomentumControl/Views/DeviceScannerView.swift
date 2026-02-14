import SwiftUI

struct DeviceScannerView: View {
    @Bindable var viewModel: HeadphoneViewModel
    @State private var isAutoConnecting = false

    var body: some View {
        VStack(spacing: 16) {
            // Hero icon
            VStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.system(size: 40, weight: .light))
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
            }

            // Monitoring indicator
            if viewModel.state.connectionStatus == .disconnected {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Monitoring for devices...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Known Sennheiser devices
            let knownDevices = MACResolver.listSennheiserDevices()
            if !knownDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Known Devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(knownDevices, id: \.address) { device in
                        Button {
                            Task {
                                viewModel.state.deviceName = device.name
                                await viewModel.connect(to: device.address)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "headphones")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name)
                                        .font(.callout)
                                    Text(device.address)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
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
                        HStack(spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                    .font(.callout)
                                Text("RSSI: \(device.rssi)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            await viewModel.autoConnect()
        }
    }
}
