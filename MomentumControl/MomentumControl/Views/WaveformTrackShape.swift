import SwiftUI

/// Draws waveform bars along a horizontal track.
/// `sliderValue` (0–100) controls the waveform shape:
/// - Near 0 (max ANC): bars are compressed/flat
/// - Near 50 (boundary): bars transition
/// - Near 100 (max Transparency): bars are tall/open
struct WaveformTrackShape: Shape {
    var sliderValue: Double

    var animatableData: Double {
        get { sliderValue }
        set { sliderValue = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let barCount = 32
        let barWidth: CGFloat = 2
        let spacing = rect.width / CGFloat(barCount)
        let centerY = rect.midY

        for i in 0..<barCount {
            let x = spacing * CGFloat(i) + spacing / 2
            let normalizedPosition = CGFloat(i) / CGFloat(barCount - 1) // 0 to 1

            // Bar height depends on position along track and slider value
            let baseHeight: CGFloat = 2.0
            let maxHeight = rect.height * 0.8

            // Waveform pattern: pseudo-random heights using sine
            let wave = abs(sin(CGFloat(i) * 1.3 + 0.7) * cos(CGFloat(i) * 0.9 + 0.3))

            // How "active" this position is based on slider value
            let sliderNormalized = CGFloat(sliderValue) / 100.0
            let distanceFromSlider = abs(normalizedPosition - sliderNormalized)
            let proximity = max(0, 1.0 - distanceFromSlider * 3.0)

            // ANC side (left): compressed. Transparency side (right): open.
            let sideFactor: CGFloat
            if normalizedPosition < 0.5 {
                sideFactor = sliderNormalized < 0.5 ? 0.2 : 0.5
            } else {
                sideFactor = sliderNormalized > 0.5 ? 1.0 : 0.4
            }

            let height = max(baseHeight, maxHeight * wave * sideFactor * (0.3 + proximity * 0.7))

            let barRect = CGRect(
                x: x - barWidth / 2,
                y: centerY - height / 2,
                width: barWidth,
                height: height
            )
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: 1, height: 1))
        }

        return path
    }
}
