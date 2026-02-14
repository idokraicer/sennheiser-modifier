import SwiftUI

struct ANCControlView: View {
    @Bindable var viewModel: HeadphoneViewModel

    @State private var sliderValue: Double = 50
    @State private var isDragging: Bool = false

    private var isOff: Bool {
        viewModel.state.ancMode == .off
    }

    private var accentColor: Color {
        if viewModel.state.adaptiveModeEnabled {
            return viewModel.state.ancAccentColor
        }
        return DeviceState.accentColor(forSliderValue: sliderValue)
    }

    private var showAntiWind: Bool {
        !viewModel.state.adaptiveModeEnabled && !isOff
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: label + adaptive toggle
            HStack {
                if isOff {
                    Text("Off")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if viewModel.state.adaptiveModeEnabled {
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

                // Off toggle pill
                PillToggle(
                    title: "Off",
                    systemImage: "power",
                    isOn: Binding(
                        get: { isOff },
                        set: { viewModel.setOff(enabled: $0) }
                    ),
                    accentColor: .gray
                )

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
                    isDragging = true
                    viewModel.handleSliderDragging(newValue)
                },
                onCommit: { finalValue in
                    viewModel.commitSliderValue(finalValue)
                    isDragging = false
                }
            )

            // Anti-wind: visible in ANC and Transparency modes, hidden in Adaptive/Off
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
            guard !isDragging else { return }
            sliderValue = viewModel.state.unifiedSliderValue
        }
        .onChange(of: viewModel.state.transparentHearingEnabled) { _, _ in
            guard !isDragging else { return }
            sliderValue = viewModel.state.unifiedSliderValue
        }
        .onChange(of: viewModel.state.ancTransparencyLevel) { _, _ in
            guard !isDragging else { return }
            sliderValue = viewModel.state.unifiedSliderValue
        }
    }
}
