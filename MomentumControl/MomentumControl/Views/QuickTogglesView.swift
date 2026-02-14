import SwiftUI

struct QuickTogglesView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        HStack {
            PillToggle(
                title: "Bass Boost",
                systemImage: "speaker.wave.3",
                isOn: Binding(
                    get: { viewModel.state.bassBoostEnabled },
                    set: { viewModel.setBassBoost(enabled: $0) }
                ),
                accentColor: .orange
            )
            Spacer()
        }
    }
}
