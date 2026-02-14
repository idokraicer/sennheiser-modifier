import SwiftUI

/// A custom slider with three zones (ANC / Off / Transparency),
/// waveform visualization on the track, and a color-shifting thumb.
struct UnifiedANCSlider: View {
    @Binding var value: Double
    var isDisabled: Bool = false
    var onChanged: ((Double) -> Void)?

    private var accentColor: Color {
        DeviceState.accentColor(forSliderValue: value)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Slider
            GeometryReader { geometry in
                let trackHeight: CGFloat = 28
                let thumbSize: CGFloat = 22

                ZStack(alignment: .leading) {
                    // Waveform track background
                    WaveformTrackShape(sliderValue: value)
                        .fill(accentColor.opacity(0.25))
                        .frame(height: trackHeight)
                        .clipShape(RoundedRectangle(cornerRadius: trackHeight / 2))
                        .overlay {
                            RoundedRectangle(cornerRadius: trackHeight / 2)
                                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
                        }

                    // Thumb
                    Circle()
                        .fill(accentColor)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: accentColor.opacity(0.4), radius: 4, y: 2)
                        .offset(x: thumbOffset(in: geometry.size.width, thumbSize: thumbSize))
                }
                .frame(height: trackHeight)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard !isDisabled else { return }
                            let fraction = max(0, min(1, drag.location.x / geometry.size.width))
                            let snapped = snapToCenter(fraction * 100)
                            value = snapped
                            onChanged?(snapped)
                        }
                )
                .opacity(isDisabled ? 0.4 : 1.0)
                .allowsHitTesting(!isDisabled)
            }
            .frame(height: 28)

            // Zone labels
            HStack {
                Text("ANC")
                    .font(.caption2)
                    .fontWeight(value <= 39 ? .semibold : .regular)
                    .foregroundStyle(value <= 39 ? accentColor : .secondary)
                Spacer()
                Text("Off")
                    .font(.caption2)
                    .fontWeight(value > 39 && value < 61 ? .semibold : .regular)
                    .foregroundStyle(value > 39 && value < 61 ? .primary : .secondary)
                Spacer()
                Text("Transparency")
                    .font(.caption2)
                    .fontWeight(value >= 61 ? .semibold : .regular)
                    .foregroundStyle(value >= 61 ? accentColor : .secondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: value)
    }

    private func thumbOffset(in width: CGFloat, thumbSize: CGFloat) -> CGFloat {
        let usable = width - thumbSize
        return (value / 100.0) * usable
    }

    /// Snap to center (50) when within the Off dead zone.
    private func snapToCenter(_ rawValue: Double) -> Double {
        if rawValue > 44 && rawValue < 56 {
            return 50
        }
        return rawValue
    }
}
