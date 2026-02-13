import SwiftUI

struct QuickTogglesView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { viewModel.state.bassBoostEnabled },
                set: { viewModel.setBassBoost(enabled: $0) }
            )) {
                Label("Bass Boost", systemImage: "speaker.wave.3")
            }
            .font(.callout)

        }
    }
}
