import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("General")

            settingRow(
                icon: "headphones",
                title: "On Head Detection",
                isOn: Binding(
                    get: { viewModel.state.onHeadDetectionEnabled },
                    set: { viewModel.setOnHeadDetection(enabled: $0) }
                )
            )

            sectionHeader("Calls")
                .padding(.top, 6)

            settingRow(
                icon: "phone.arrow.up.right",
                title: "Auto Answer",
                isOn: Binding(
                    get: { viewModel.state.autoCallEnabled },
                    set: { viewModel.setAutoCall(enabled: $0) }
                )
            )

            Divider()
                .opacity(0.3)
                .padding(.leading, 38)

            settingRow(
                icon: "phone.circle",
                title: "Comfort Call",
                isOn: Binding(
                    get: { viewModel.state.comfortCallEnabled },
                    set: { viewModel.setComfortCall(enabled: $0) }
                )
            )
        }
        .padding(.bottom, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func settingRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.callout)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .scaleEffect(0.9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
