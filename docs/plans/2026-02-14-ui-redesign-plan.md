# UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the MomentumControl macOS menu bar popover with Control Center-inspired cards, a unified ANC slider with waveform visualization, battery ring, adaptive mode toggle, and progressive disclosure.

**Architecture:** SwiftUI views restructured into material-backed cards. New reusable components (PillToggle, BatteryRingView, UnifiedANCSlider, ExpandableSection). ViewModel updated to support unified slider mapping and adaptive-as-primary-mode. Model cleaned up (remove comfortMode).

**Tech Stack:** Swift 5.10, SwiftUI, macOS 14.0+, IOBluetooth, XcodeGen

**Design doc:** `docs/plans/2026-02-14-ui-redesign-design.md`

**Base paths:**
- Views: `MomentumControl/MomentumControl/Views/`
- Model: `MomentumControl/MomentumControl/Model/`
- ViewModel: `MomentumControl/MomentumControl/ViewModel/`
- Tests: `MomentumControl/MomentumControlTests/`

---

### Task 1: Clean up model — remove comfortMode

**Files:**
- Modify: `MomentumControl/MomentumControl/Model/DeviceState.swift`
- Modify: `MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift`

**Step 1: Remove comfortModeEnabled from DeviceState**

In `DeviceState.swift`, delete the property declaration:
```swift
var comfortModeEnabled: Bool = false
```

And remove it from the `reset()` method:
```swift
comfortModeEnabled = false
```

**Step 2: Remove comfortMode from ViewModel**

In `HeadphoneViewModel.swift`, delete the `setComfortMode` method entirely:
```swift
func setComfortMode(enabled: Bool) {
    connection.sendSet(for: .anc, values: [.uint8(0x02), .uint8(enabled ? 0x01 : 0x00)])
}
```

In `handlePropertyUpdate`, in the `"ANC"` case, remove the line:
```swift
state.comfortModeEnabled = values[3].asInt == 1
```

**Step 3: Build to verify no compilation errors**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add MomentumControl/MomentumControl/Model/DeviceState.swift MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift
git commit -m "chore: remove comfortModeEnabled from model and viewmodel"
```

---

### Task 2: Add unified slider mapping logic to ViewModel

The unified slider uses a single 0–100 value to represent three ANC zones. The ViewModel needs methods to convert between this unified value and the separate device properties.

**Files:**
- Modify: `MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift`
- Modify: `MomentumControl/MomentumControl/Model/DeviceState.swift`

**Step 1: Add unifiedSliderValue computed property to DeviceState**

Add to `DeviceState.swift` in the `// MARK: - Computed` section:

```swift
/// Unified slider value (0–100).
/// 0–39 = ANC zone, 40–60 = Off zone, 61–100 = Transparency zone.
var unifiedSliderValue: Double {
    if transparentHearingEnabled {
        // Transparency zone: 61–100
        return 61.0 + 39.0 // Full transparency = 100
    } else if ancEnabled {
        // ANC zone: 0–39, where 0 = full ANC, 39 = light ANC
        // ancTransparencyLevel 0 = full cancellation, 100 = max ambient pass-through
        let mapped = Double(ancTransparencyLevel) / 100.0 * 39.0
        return mapped
    } else {
        return 50.0 // Off
    }
}
```

**Step 2: Add setUnifiedSliderValue method to ViewModel**

Add to `HeadphoneViewModel.swift`:

```swift
/// Maps a unified slider value (0–100) to ANC mode + transparency commands.
/// 0–39 = ANC zone, 40–60 = Off zone, 61–100 = Transparency zone.
func setUnifiedSliderValue(_ value: Double) {
    if value <= 39 {
        // ANC zone
        let transparencyLevel = Int(value / 39.0 * 100.0)
        state.ancEnabled = true
        state.transparentHearingEnabled = false
        state.ancTransparencyLevel = transparencyLevel
        state.ancMode = .anc

        connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
        connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])

        // Debounce the transparency level
        transparencyDebounceTask?.cancel()
        transparencyDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            connection.sendSet(for: .ancTransparency, values: [.uint8(UInt8(clamping: min(transparencyLevel, 100)))])
        }
    } else if value >= 61 {
        // Transparency zone
        state.ancEnabled = false
        state.transparentHearingEnabled = true
        state.ancMode = .transparency

        connection.sendSet(for: .ancStatus, values: [.uint8(0x00)])
        connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x01)])
    } else {
        // Off zone (40–60)
        state.ancEnabled = false
        state.transparentHearingEnabled = false
        state.ancMode = .off

        connection.sendSet(for: .ancStatus, values: [.uint8(0x00)])
        connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
    }
}

/// Human-readable label for the current unified slider position.
func unifiedSliderLabel(for value: Double) -> String {
    if value <= 39 {
        let pct = Int((1.0 - value / 39.0) * 100)
        return "ANC \(pct)%"
    } else if value >= 61 {
        let pct = Int((value - 61.0) / 39.0 * 100)
        return "Transparency \(pct)%"
    } else {
        return "Off"
    }
}

/// Whether the slider is in the ANC zone (for showing sub-controls).
func isInANCZone(value: Double) -> Bool {
    value <= 39
}
```

**Step 3: Add adaptive mode toggle method to ViewModel**

Add to `HeadphoneViewModel.swift`:

```swift
func setAdaptiveANC(enabled: Bool) {
    state.adaptiveModeEnabled = enabled
    connection.sendSet(for: .anc, values: [.uint8(0x03), .uint8(enabled ? 0x01 : 0x00)])
    if enabled {
        // When adaptive is on, also enable ANC
        state.ancEnabled = true
        state.transparentHearingEnabled = false
        state.ancMode = .anc
        connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
        connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
    }
}
```

**Step 4: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift MomentumControl/MomentumControl/Model/DeviceState.swift
git commit -m "feat: add unified slider mapping and adaptive mode toggle to ViewModel"
```

---

### Task 3: Add ANC accent color to model

The UI needs a dynamic accent color that shifts with ANC mode. Add this as a computed property on DeviceState so all views can access it.

**Files:**
- Modify: `MomentumControl/MomentumControl/Model/DeviceState.swift`

**Step 1: Add accent color computed property**

Add to `DeviceState.swift` in the `// MARK: - Computed` section. Import SwiftUI at the top of the file.

```swift
import SwiftUI
```

```swift
/// Dynamic accent color based on current ANC mode.
var ancAccentColor: Color {
    if adaptiveModeEnabled {
        return Color(red: 0.55, green: 0.45, blue: 0.85) // Soft purple
    }
    if transparentHearingEnabled {
        return Color(red: 0.9, green: 0.65, blue: 0.3)   // Warm amber
    }
    if ancEnabled {
        return Color(red: 0.3, green: 0.6, blue: 0.95)   // Cool blue
    }
    return Color.gray
}

/// Accent color for a specific unified slider position (for continuous color shift).
static func accentColor(forSliderValue value: Double) -> Color {
    if value <= 39 {
        // ANC zone: cool blue, more saturated toward 0
        let intensity = 1.0 - (value / 39.0) * 0.3
        return Color(red: 0.3 * intensity, green: 0.6 * intensity, blue: 0.95)
    } else if value >= 61 {
        // Transparency zone: warm amber, more saturated toward 100
        let intensity = 0.7 + ((value - 61.0) / 39.0) * 0.3
        return Color(red: 0.9 * intensity, green: 0.65 * intensity, blue: 0.3)
    } else {
        return Color.gray
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Model/DeviceState.swift
git commit -m "feat: add dynamic ANC accent color to DeviceState"
```

---

### Task 4: Create PillToggle reusable component

A custom capsule-shaped toggle button used throughout the redesigned UI.

**Files:**
- Create: `MomentumControl/MomentumControl/Views/PillToggle.swift`

**Step 1: Create PillToggle view**

```swift
import SwiftUI

/// A custom capsule-shaped toggle with icon and optional label.
/// When off: outlined stroke, secondary color.
/// When on: filled with accent color, icon turns white, scale-up spring animation.
struct PillToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var accentColor: Color = .blue

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? .white : .secondary)
            .background {
                Capsule()
                    .fill(isOn ? accentColor : Color.clear)
            }
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isOn ? 1.02 : 1.0)
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/PillToggle.swift
git commit -m "feat: add PillToggle reusable component"
```

---

### Task 5: Create BatteryRingView

A circular battery indicator drawn around the headphone icon.

**Files:**
- Create: `MomentumControl/MomentumControl/Views/BatteryRingView.swift`

**Step 1: Create BatteryRingView**

```swift
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
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/BatteryRingView.swift
git commit -m "feat: add BatteryRingView with circular battery indicator"
```

---

### Task 6: Create WaveformTrackShape

A custom Shape that draws waveform bars along a horizontal track. Bars compress toward the ANC end and open up toward the Transparency end.

**Files:**
- Create: `MomentumControl/MomentumControl/Views/WaveformTrackShape.swift`

**Step 1: Create WaveformTrackShape**

```swift
import SwiftUI

/// Draws waveform bars along a horizontal track.
/// `sliderValue` (0–100) controls the waveform shape:
/// - Near 0 (ANC): bars are compressed/flat
/// - Near 50 (Off): bars are minimal/dormant
/// - Near 100 (Transparency): bars are tall/open
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
            if normalizedPosition < 0.4 {
                // ANC zone: bars are flat when slider is here (cancelling noise)
                sideFactor = sliderNormalized < 0.4 ? 0.2 : 0.5
            } else if normalizedPosition > 0.6 {
                // Transparency zone: bars are tall when slider is here (letting sound through)
                sideFactor = sliderNormalized > 0.6 ? 1.0 : 0.4
            } else {
                // Off zone: minimal
                sideFactor = 0.3
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
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/WaveformTrackShape.swift
git commit -m "feat: add WaveformTrackShape for ANC slider visualization"
```

---

### Task 7: Create UnifiedANCSlider

The custom slider component with waveform track, zone labels, and continuous color shifting.

**Files:**
- Create: `MomentumControl/MomentumControl/Views/UnifiedANCSlider.swift`

**Step 1: Create UnifiedANCSlider**

```swift
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
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/UnifiedANCSlider.swift
git commit -m "feat: add UnifiedANCSlider with waveform track and color shifting"
```

---

### Task 8: Create ExpandableSection

A generic disclosure container with rotating chevron animation.

**Files:**
- Create: `MomentumControl/MomentumControl/Views/ExpandableSection.swift`

**Step 1: Create ExpandableSection**

```swift
import SwiftUI

/// A disclosure section with a "More" label and rotating chevron.
/// Content slides down and fades in when expanded.
struct ExpandableSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/ExpandableSection.swift
git commit -m "feat: add ExpandableSection disclosure container"
```

---

### Task 9: Redesign DeviceHeaderView

Replace the current header (icon + text + battery bar) with the new card-based header with battery ring.

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/DeviceHeaderView.swift`

**Step 1: Rewrite DeviceHeaderView**

Replace the entire file contents:

```swift
import SwiftUI

struct DeviceHeaderView: View {
    let state: DeviceState

    var body: some View {
        HStack(spacing: 12) {
            // Battery ring with headphone icon
            BatteryRingView(
                percent: state.batteryPercent,
                isCharging: state.isCharging
            )

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(state.deviceName)
                    .font(.headline)
                    .lineLimit(1)

                if let firmware = state.firmwareVersion {
                    Text("v\(firmware)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Battery percentage
            Text("\(state.batteryPercent)%")
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(state.isCharging ? .green : .primary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/DeviceHeaderView.swift
git commit -m "redesign: DeviceHeaderView with battery ring and material card"
```

---

### Task 10: Redesign ANCControlView

The hero tile: unified slider, adaptive toggle, conditional anti-wind, colored glow halo.

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/ANCControlView.swift`

**Step 1: Rewrite ANCControlView**

Replace the entire file contents:

```swift
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
                isDisabled: viewModel.state.adaptiveModeEnabled
            ) { newValue in
                viewModel.setUnifiedSliderValue(newValue)
            }

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
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/ANCControlView.swift
git commit -m "redesign: ANCControlView with unified slider, adaptive toggle, and glow halo"
```

---

### Task 11: Redesign QuickTogglesView

Replace the standard Toggle with PillToggle. Remove section header.

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/QuickTogglesView.swift`

**Step 1: Rewrite QuickTogglesView**

Replace the entire file contents:

```swift
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
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/QuickTogglesView.swift
git commit -m "redesign: QuickTogglesView with PillToggle"
```

---

### Task 12: Redesign ConnectedDevicesView

Material card, status dots, text button actions.

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/ConnectedDevicesView.swift`

**Step 1: Rewrite ConnectedDevicesView**

Replace the entire file contents:

```swift
import SwiftUI

struct ConnectedDevicesView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paired Devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(viewModel.state.pairedDeviceCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            if viewModel.state.pairedDevices.isEmpty && viewModel.state.pairedDeviceCount > 0 {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.state.pairedDevices) { device in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(device.isConnected ? Color.green : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)

                        Text(device.name)
                            .font(.callout)
                            .lineLimit(1)

                        Spacer()

                        if device.isConnected {
                            Button("Disconnect") {
                                viewModel.disconnectPairedDevice(index: device.index)
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        } else {
                            Button("Connect") {
                                viewModel.connectPairedDevice(index: device.index)
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/ConnectedDevicesView.swift
git commit -m "redesign: ConnectedDevicesView with status dots and material card"
```

---

### Task 13: Redesign SettingsView

Call settings as pill toggles in a row inside a material card.

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/SettingsView.swift`

**Step 1: Rewrite SettingsView**

Replace the entire file contents:

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: HeadphoneViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Call Settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                PillToggle(
                    title: "Auto Answer",
                    systemImage: "phone.arrow.up.right",
                    isOn: Binding(
                        get: { viewModel.state.autoCallEnabled },
                        set: { viewModel.setAutoCall(enabled: $0) }
                    ),
                    accentColor: .green
                )

                PillToggle(
                    title: "Comfort Call",
                    systemImage: "phone.circle",
                    isOn: Binding(
                        get: { viewModel.state.comfortCallEnabled },
                        set: { viewModel.setComfortCall(enabled: $0) }
                    ),
                    accentColor: .green
                )

                Spacer()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/SettingsView.swift
git commit -m "redesign: SettingsView with PillToggle call settings"
```

---

### Task 14: Redesign PopoverContentView

Root layout with progressive disclosure. Remove dividers, add expandable "More" section.

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/PopoverContentView.swift`

**Step 1: Rewrite PopoverContentView**

Replace the entire file contents:

```swift
import SwiftUI

struct PopoverContentView: View {
    @Bindable var viewModel: HeadphoneViewModel
    @State private var isMoreExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.connectionStatus.isConnected {
                ScrollView {
                    VStack(spacing: 12) {
                        DeviceHeaderView(state: viewModel.state)
                        ANCControlView(viewModel: viewModel)
                        QuickTogglesView(viewModel: viewModel)

                        ExpandableSection(
                            title: "More",
                            isExpanded: $isMoreExpanded
                        ) {
                            VStack(spacing: 8) {
                                ConnectedDevicesView(viewModel: viewModel)
                                SettingsView(viewModel: viewModel)
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                DeviceScannerView(viewModel: viewModel)
                    .padding(12)
            }

            // Footer
            HStack {
                if viewModel.state.connectionStatus.isConnected {
                    Button("Disconnect") {
                        viewModel.disconnect()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/PopoverContentView.swift
git commit -m "redesign: PopoverContentView with progressive disclosure layout"
```

---

### Task 15: Style DeviceScannerView to match new design

Update the scanner view to use material cards and match the visual language.

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/DeviceScannerView.swift`

**Step 1: Rewrite DeviceScannerView**

Replace the entire file contents:

```swift
import SwiftUI

struct DeviceScannerView: View {
    @Bindable var viewModel: HeadphoneViewModel
    @State private var isAutoConnecting = false

    var body: some View {
        VStack(spacing: 16) {
            // Hero icon
            VStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)

                Text("MomentumControl")
                    .font(.headline)

                Text(viewModel.state.connectionStatus.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .error(let msg) = viewModel.state.connectionStatus {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }

            // Known Sennheiser devices
            let knownDevices = MACResolver.listSennheiserDevices()
            if !knownDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Known Devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(knownDevices, id: \.address) { device in
                        Button {
                            Task {
                                viewModel.state.deviceName = device.name
                                await viewModel.connect(to: device.address)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "headphones")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name)
                                        .font(.callout)
                                    Text(device.address)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // BLE Scanner
            VStack(spacing: 8) {
                if viewModel.bleScanner.isScanning {
                    ProgressView("Scanning...")
                        .font(.caption)
                } else {
                    Button("Scan for Devices") {
                        viewModel.bleScanner.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                ForEach(viewModel.bleScanner.discoveredDevices) { device in
                    Button {
                        Task {
                            viewModel.bleScanner.stopScan()
                            if let mac = MACResolver.resolve(deviceName: device.name) {
                                viewModel.state.deviceName = device.name
                                await viewModel.connect(to: mac)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                    .font(.callout)
                                Text("RSSI: \(device.rssi)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Auto-connect
            if !isAutoConnecting && !knownDevices.isEmpty {
                Button("Auto-Connect") {
                    isAutoConnecting = true
                    Task {
                        await viewModel.autoConnect()
                        isAutoConnecting = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .task {
            await viewModel.autoConnect()
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/DeviceScannerView.swift
git commit -m "redesign: DeviceScannerView with material cards matching new design language"
```

---

### Task 16: Remove old setANCMode and setAdaptiveMode methods

Clean up the ViewModel by removing methods that are replaced by the unified slider approach. Keep `setAntiWind` since it's still used.

**Files:**
- Modify: `MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift`

**Step 1: Remove replaced methods**

Delete the `setANCMode(_ mode: ANCMode)` method entirely (lines ~296–325 in current file). The unified slider's `setUnifiedSliderValue` replaces it.

Delete the old `setAdaptiveMode(enabled: Bool)` method (the one that only sends a single ANC sub-property command). The new `setAdaptiveANC(enabled: Bool)` from Task 2 replaces it.

Delete the old `setTransparencyLevel(_ level: Int)` method. The unified slider handles transparency level as part of `setUnifiedSliderValue`.

**Step 2: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Run existing tests**

Run: `cd MomentumControl && xcodebuild test -project MomentumControl.xcodeproj -scheme MomentumControl 2>&1 | tail -10`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift
git commit -m "chore: remove old ANC methods replaced by unified slider"
```

---

### Task 17: Final build verification and polish

Full clean build and visual review.

**Step 1: Clean build**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug clean build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 2: Run all tests**

Run: `cd MomentumControl && xcodebuild test -project MomentumControl.xcodeproj -scheme MomentumControl 2>&1 | tail -10`
Expected: All tests pass.

**Step 3: Commit any remaining changes**

```bash
git add -A && git status
# Only commit if there are changes
git commit -m "redesign: UI redesign complete — Control Center cards with unified ANC slider"
```
