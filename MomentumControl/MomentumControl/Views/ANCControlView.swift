import SwiftUI

struct ANCControlView: View {
    @Bindable var viewModel: HeadphoneViewModel

    private var transparencyLabel: String {
        let level = viewModel.state.ancTransparencyLevel
        if level <= 0 {
            return "ANC 100%"
        } else if level >= 100 {
            return "Transparency 100%"
        } else if level <= 50 {
            let pct = 100 - level * 2
            return "ANC \(pct)%"
        } else {
            let pct = (level - 50) * 2
            return "Transparency \(pct)%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Noise Control")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // ANC Mode Picker
            Picker("Mode", selection: Binding(
                get: { viewModel.state.effectiveANCMode },
                set: { viewModel.setANCMode($0) }
            )) {
                ForEach(ANCMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // ANC transparency level slider & sub-options (only when in ANC mode)
            // ANC_Transparency controls how much ambient sound passes through during active noise cancellation.
            // This matches the C++ ANCCardHelper which shows these controls when ANC is enabled.
            if viewModel.state.effectiveANCMode == .anc {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Transparency Level")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(transparencyLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Image(systemName: "ear")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.state.ancTransparencyLevel) },
                                set: { viewModel.setTransparencyLevel(Int($0)) }
                            ),
                            in: 0...100,
                            step: 1
                        )

                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                VStack(spacing: 8) {
                    Toggle("Anti-Wind", isOn: Binding(
                        get: { viewModel.state.antiWindEnabled },
                        set: { viewModel.setAntiWind(enabled: $0) }
                    ))
                    .font(.caption)

                    Toggle("Adaptive", isOn: Binding(
                        get: { viewModel.state.adaptiveModeEnabled },
                        set: { viewModel.setAdaptiveMode(enabled: $0) }
                    ))
                    .font(.caption)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.state.effectiveANCMode)
    }
}
