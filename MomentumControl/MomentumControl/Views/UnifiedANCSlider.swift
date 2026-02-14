import SwiftUI
import AppKit

/// Captures trackpad scroll wheel events and reports horizontal delta.
private struct ScrollWheelView: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    var onScrollEnd: () -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onScrollEnd = onScrollEnd
    }
}

private class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    var onScrollEnd: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .ended || event.momentumPhase == .ended {
            onScrollEnd?()
        } else if event.phase == .changed || event.momentumPhase == .changed {
            // Use scrollingDeltaX for horizontal scroll; negate so swipe-right = increase
            let delta = event.scrollingDeltaX
            onScroll?(delta)
        }
    }
}

/// A custom slider with three zones (ANC / Off / Transparency),
/// waveform visualization on the track, and a color-shifting thumb.
struct UnifiedANCSlider: View {
    @Binding var value: Double
    var isDisabled: Bool = false
    var onDragging: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    @State private var thumbScale: CGFloat = 1.0
    @State private var currentZone: Int = 1 // 0=ANC, 1=Off, 2=Transparency

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
                        .scaleEffect(thumbScale)
                        .offset(x: thumbOffset(in: geometry.size.width, thumbSize: thumbSize))
                }
                .frame(height: trackHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard !isDisabled else { return }
                            let fraction = max(0, min(1, drag.location.x / geometry.size.width))
                            let snapped = snapToCenter(fraction * 100)
                            value = snapped

                            // Zone-change detent feedback
                            let newZone = zoneIndex(for: snapped)
                            if newZone != currentZone {
                                currentZone = newZone
                                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                                    thumbScale = 1.15
                                }
                                withAnimation(.spring(response: 0.15, dampingFraction: 0.5).delay(0.1)) {
                                    thumbScale = 1.0
                                }
                            }

                            onDragging?(snapped)
                        }
                        .onEnded { drag in
                            guard !isDisabled else { return }
                            // Compute position from drag location directly,
                            // in case .onChanged didn't fire (macOS click without drag)
                            let fraction = max(0, min(1, drag.location.x / geometry.size.width))
                            let snapped = snapToCenter(fraction * 100)
                            value = snapped
                            onDragging?(snapped)
                            onCommit?(snapped)
                        }
                )
                .overlay {
                    // Trackpad two-finger horizontal scroll
                    ScrollWheelView(
                        onScroll: { delta in
                            guard !isDisabled else { return }
                            let step = delta * 0.5 // Scale: ~2 full swipes to traverse 0-100
                            let newValue = snapToCenter(max(0, min(100, value + Double(step))))
                            value = newValue

                            let newZone = zoneIndex(for: newValue)
                            if newZone != currentZone {
                                currentZone = newZone
                                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                                    thumbScale = 1.15
                                }
                                withAnimation(.spring(response: 0.15, dampingFraction: 0.5).delay(0.1)) {
                                    thumbScale = 1.0
                                }
                            }

                            onDragging?(newValue)
                        },
                        onScrollEnd: {
                            guard !isDisabled else { return }
                            onCommit?(value)
                        }
                    )
                }
                .opacity(isDisabled ? 0.4 : 1.0)
                .allowsHitTesting(!isDisabled)
            }
            .frame(height: 28)

            // Zone labels — positioned at each zone's center
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack {
                    Text("ANC")
                        .font(.caption2)
                        .fontWeight(value <= 39 ? .semibold : .regular)
                        .foregroundStyle(value <= 39 ? accentColor : .secondary)
                        .position(x: width * 0.195, y: 6)

                    Text("Off")
                        .font(.caption2)
                        .fontWeight(value > 39 && value < 61 ? .semibold : .regular)
                        .foregroundStyle(value > 39 && value < 61 ? .primary : .secondary)
                        .position(x: width * 0.5, y: 6)

                    Text("Transparency")
                        .font(.caption2)
                        .fontWeight(value >= 61 ? .semibold : .regular)
                        .foregroundStyle(value >= 61 ? accentColor : .secondary)
                        .position(x: width * 0.805, y: 6)
                }
            }
            .frame(height: 12)
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

    /// Zone index for detent detection: 0=ANC, 1=Off, 2=Transparency
    private func zoneIndex(for value: Double) -> Int {
        if value <= 39 { return 0 }
        if value >= 61 { return 2 }
        return 1
    }
}
