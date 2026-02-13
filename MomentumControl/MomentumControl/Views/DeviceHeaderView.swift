import SwiftUI

struct DeviceHeaderView: View {
    let state: DeviceState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "headphones")
                    .font(.title)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.deviceName)
                        .font(.headline)

                    if let firmware = state.firmwareVersion {
                        Text("Firmware \(firmware)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Battery indicator
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: state.batteryIcon)
                            .foregroundStyle(batteryColor)
                        Text("\(state.batteryPercent)%")
                            .font(.headline)
                            .monospacedDigit()
                    }

                    if state.isCharging {
                        Text("Charging")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            // Battery bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(batteryColor)
                        .frame(width: geometry.size.width * CGFloat(state.batteryPercent) / 100.0, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private var batteryColor: Color {
        switch state.batteryPercent {
        case 0..<20: .red
        case 20..<50: .orange
        default: .green
        }
    }
}
