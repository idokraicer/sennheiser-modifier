import SwiftUI

struct ANCControlView: View {
    @Bindable var viewModel: HeadphoneViewModel

    @State private var sliderValue: Double = 50

    private var accentColor: Color {
        if viewModel.state.adaptiveModeEnabled {
            return viewModel.state.ancAccentColor
        }
        return DeviceState.accentColor(forSliderValue: sliderValue)
    }

    private var showAntiWind: Bool {
        !viewModel.state.adaptiveModeEnabled && viewModel.isInANCZone(value: sliderValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: label + adaptive toggle
            HStack {
                if viewModel.state.adaptiveModeEnabled {
                    Text("Adaptive ANC")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                } else {
                    Text(viewModel.unifiedSliderLabel(for: sliderValue))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                }

                Spacer()

                // Adaptive toggle pill
                PillToggle(
                    title: "Adaptive",
                    systemImage: "waveform.badge.magnifyingglass",
                    isOn: Binding(
                        get: { viewModel.state.adaptiveModeEnabled },
                        set: { viewModel.setAdaptiveANC(enabled: $0) }
                    ),
                    accentColor: Color(red: 0.55, green: 0.45, blue: 0.85)
                )
            }

            // Unified slider
            UnifiedANCSlider(
                value: $sliderValue,
                isDisabled: viewModel.state.adaptiveModeEnabled,
                onDragging: { newValue in
                    viewModel.handleSliderDragging(newValue)
                },
                onCommit: { finalValue in
                    viewModel.commitSliderValue(finalValue)
                }
            )

            // Conditional anti-wind (ANC zone only, adaptive off)
            if showAntiWind {
                PillToggle(
                    title: "Anti-Wind",
                    systemImage: "wind",
                    isOn: Binding(
                        get: { viewModel.state.antiWindEnabled },
                        set: { viewModel.setAntiWind(enabled: $0) }
                    ),
                    accentColor: accentColor
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
        .background {
            // Glow halo behind the card
            RoundedRectangle(cornerRadius: 20)
                .fill(accentColor.opacity(0.15))
                .blur(radius: 12)
                .offset(y: 2)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showAntiWind)
        .animation(.easeInOut(duration: 0.3), value: viewModel.state.adaptiveModeEnabled)
        .onAppear {
            sliderValue = viewModel.state.unifiedSliderValue
        }
        .onChange(of: viewModel.state.ancEnabled) { _, _ in
            sliderValue = viewModel.state.unifiedSliderValue
        }
        .onChange(of: viewModel.state.transparentHearingEnabled) { _, _ in
            sliderValue = viewModel.state.unifiedSliderValue
        }
    }
}
