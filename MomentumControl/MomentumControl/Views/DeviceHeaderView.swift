import SwiftUI

struct DeviceHeaderView: View {
    let state: DeviceState

    var body: some View {
        HStack(spacing: 12) {
            // Battery ring with headphone icon
            BatteryRingView(
                percent: state.batteryPercent,
                isCharging: state.isCharging
            )

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(state.deviceName)
                    .font(.headline)
                    .lineLimit(1)

                if let firmware = state.firmwareVersion {
                    Text("v\(firmware)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Battery percentage
            Text("\(state.batteryPercent)%")
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(state.isCharging ? .green : .primary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
