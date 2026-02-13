import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Call Settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { viewModel.state.autoCallEnabled },
                set: { viewModel.setAutoCall(enabled: $0) }
            )) {
                Label("Auto Answer Call", systemImage: "phone.arrow.up.right")
            }
            .font(.callout)

            Toggle(isOn: Binding(
                get: { viewModel.state.comfortCallEnabled },
                set: { viewModel.setComfortCall(enabled: $0) }
            )) {
                Label("Comfort Call", systemImage: "phone.circle")
            }
            .font(.callout)
        }
    }
}
