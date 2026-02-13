import SwiftUI

struct MenuBarIcon: View {
    let state: DeviceState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "headphones")
            if state.connectionStatus.isConnected {
                Text("\(state.batteryPercent)%")
                    .font(.caption2)
            }
        }
    }
}
