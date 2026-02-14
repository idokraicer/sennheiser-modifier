import SwiftUI
import AppKit

/// A custom slider with two zones (ANC / Transparency),
/// waveform visualization on the track, and a color-shifting thumb.
struct UnifiedANCSlider: View {
    @Binding var value: Double
    var isDisabled: Bool = false
    var onDragging: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    @State private var thumbScale: CGFloat = 1.0
    @State private var currentZone: Int = 0 // 0=ANC, 1=Transparency
    @State private var isHovered: Bool = false
    @State private var scrollMonitor: Any?

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
                            applyDetent(for: snapped)
                            onDragging?(snapped)
                        }
                        .onEnded { drag in
                            guard !isDisabled else { return }
                            let fraction = max(0, min(1, drag.location.x / geometry.size.width))
                            let snapped = snapToCenter(fraction * 100)
                            value = snapped
                            onDragging?(snapped)
                            onCommit?(snapped)
                        }
                )
                .onHover { hovering in
                    isHovered = hovering
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
                        .fontWeight(value <= 50 ? .semibold : .regular)
                        .foregroundStyle(value <= 50 ? accentColor : .secondary)
                        .position(x: width * 0.25, y: 6)

                    Text("Transparency")
                        .font(.caption2)
                        .fontWeight(value > 50 ? .semibold : .regular)
                        .foregroundStyle(value > 50 ? accentColor : .secondary)
                        .position(x: width * 0.75, y: 6)
                }
            }
            .frame(height: 12)
        }
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
    }

    // MARK: - Scroll Wheel (trackpad two-finger horizontal)

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            guard isHovered, !isDisabled else { return event }

            if event.phase == .changed || event.momentumPhase == .changed {
                let step = event.scrollingDeltaX * 0.5
                let newValue = snapToCenter(max(0, min(100, value + Double(step))))
                value = newValue
                applyDetent(for: newValue)
                onDragging?(newValue)
                return nil // consume the event
            } else if event.phase == .ended || event.momentumPhase == .ended {
                onCommit?(value)
                return nil
            }
            return event
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Helpers

    private func thumbOffset(in width: CGFloat, thumbSize: CGFloat) -> CGFloat {
        let usable = width - thumbSize
        return (value / 100.0) * usable
    }

    /// Snap to center (50) only when crossing into the boundary zone from outside.
    /// Once inside the 48–52 range, allow free movement to prevent trapping
    /// scroll gestures (small deltas would otherwise loop: 50 → 50.5 → snap → 50).
    private func snapToCenter(_ rawValue: Double) -> Double {
        let inSnapZone = rawValue > 48 && rawValue < 52
        let wasOutsideANC = value < 48
        let wasOutsideTrans = value > 52
        if inSnapZone && (wasOutsideANC || wasOutsideTrans) {
            return 50
        }
        return rawValue
    }

    /// Zone index for detent detection: 0=ANC, 1=Transparency
    private func zoneIndex(for value: Double) -> Int {
        if value <= 50 { return 0 }
        return 1
    }

    /// Thumb scale pulse when crossing a zone boundary.
    private func applyDetent(for newValue: Double) {
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
    }
}
