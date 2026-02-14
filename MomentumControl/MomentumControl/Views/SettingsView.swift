import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Call Settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                PillToggle(
                    title: "Auto Answer",
                    systemImage: "phone.arrow.up.right",
                    isOn: Binding(
                        get: { viewModel.state.autoCallEnabled },
                        set: { viewModel.setAutoCall(enabled: $0) }
                    ),
                    accentColor: .green
                )

                PillToggle(
                    title: "Comfort Call",
                    systemImage: "phone.circle",
                    isOn: Binding(
                        get: { viewModel.state.comfortCallEnabled },
                        set: { viewModel.setComfortCall(enabled: $0) }
                    ),
                    accentColor: .green
                )

                Spacer()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
