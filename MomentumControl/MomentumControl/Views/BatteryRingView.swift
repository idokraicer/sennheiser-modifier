import SwiftUI

/// Headphone icon surrounded by a circular battery ring.
/// Ring fills proportionally to battery percentage. Pulses when charging.
struct BatteryRingView: View {
    let percent: Int
    let isCharging: Bool

    @State private var pulseOpacity: Double = 1.0

    private var ringColor: Color {
        switch percent {
        case 0..<20: .red
        case 20..<50: .orange
        default: .green
        }
    }

    private var ringProgress: Double {
        Double(max(0, min(percent, 100))) / 100.0
    }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 3)
                .frame(width: 40, height: 40)

            // Battery ring
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
                .opacity(isCharging ? pulseOpacity : 1.0)

            // Headphone icon
            Image(systemName: "headphones")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
        .onChange(of: isCharging) { _, charging in
            if charging {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.4
                }
            } else {
                withAnimation(.default) {
                    pulseOpacity = 1.0
                }
            }
        }
        .onAppear {
            if isCharging {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.4
                }
            }
        }
    }
}
