# ANC Slider Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the ANC slider to stop flooding Bluetooth with redundant commands, support click-to-jump, add detent feedback at zone boundaries, and center the "Off" label.

**Architecture:** Two-layer approach — visual layer updates UI every frame for smooth feel, command layer only sends Bluetooth commands on zone boundary crossings (immediately), debounced ANC level (~300ms), and final commit on release.

**Tech Stack:** Swift 5.10, SwiftUI, IOBluetooth (existing)

---

### Task 1: Add `lastSentZone` and `handleSliderDragging` to HeadphoneViewModel

**Files:**
- Modify: `MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift:15` (add property)
- Modify: `MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift:306-341` (replace method)

**Step 1: Add `lastSentZone` property**

At line 15, after `transparencyDebounceTask`, add:

```swift
/// Tracks the last ANC zone sent to the headset to avoid redundant mode-switch commands.
private var lastSentZone: ANCMode?
```

**Step 2: Add zone helper**

Below `isInANCZone` (around line 359), add:

```swift
/// Derive the ANC zone from a unified slider value.
private func zoneForSliderValue(_ value: Double) -> ANCMode {
    if value <= 39 { return .anc }
    if value >= 61 { return .transparency }
    return .off
}
```

**Step 3: Add `handleSliderDragging` method**

Below the new `zoneForSliderValue`, add:

```swift
/// Called on every drag frame. Updates state for UI, sends Bluetooth commands only on zone change or debounced ANC level.
func handleSliderDragging(_ value: Double) {
    let zone = zoneForSliderValue(value)

    // Always update state for UI responsiveness
    switch zone {
    case .anc:
        let transparencyLevel = Int(value / 39.0 * 100.0)
        state.ancEnabled = true
        state.transparentHearingEnabled = false
        state.ancTransparencyLevel = transparencyLevel
        state.ancMode = .anc
    case .transparency:
        state.ancEnabled = false
        state.transparentHearingEnabled = true
        state.ancMode = .transparency
    case .off:
        state.ancEnabled = false
        state.transparentHearingEnabled = false
        state.ancMode = .off
    }

    // Only send mode-switch commands when zone actually changes
    if zone != lastSentZone {
        lastSentZone = zone
        switch zone {
        case .anc:
            connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
            connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
        case .transparency:
            connection.sendSet(for: .ancStatus, values: [.uint8(0x00)])
            connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x01)])
        case .off:
            connection.sendSet(for: .ancStatus, values: [.uint8(0x00)])
            connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
        }
    }

    // Debounce ANC transparency level within ANC zone
    if zone == .anc {
        let transparencyLevel = Int(value / 39.0 * 100.0)
        transparencyDebounceTask?.cancel()
        transparencyDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            connection.sendSet(for: .ancTransparency, values: [.uint8(UInt8(clamping: min(transparencyLevel, 100)))])
        }
    }
}
```

**Step 4: Add `commitSliderValue` method**

Below `handleSliderDragging`, add:

```swift
/// Called on drag end. Sends the definitive commands so headset matches final UI state.
func commitSliderValue(_ value: Double) {
    let zone = zoneForSliderValue(value)
    lastSentZone = zone

    switch zone {
    case .anc:
        let transparencyLevel = Int(value / 39.0 * 100.0)
        state.ancEnabled = true
        state.transparentHearingEnabled = false
        state.ancTransparencyLevel = transparencyLevel
        state.ancMode = .anc

        connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
        connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])

        // Cancel any pending debounce — send exact level immediately
        transparencyDebounceTask?.cancel()
        connection.sendSet(for: .ancTransparency, values: [.uint8(UInt8(clamping: min(transparencyLevel, 100)))])
    case .transparency:
        state.ancEnabled = false
        state.transparentHearingEnabled = true
        state.ancMode = .transparency

        connection.sendSet(for: .ancStatus, values: [.uint8(0x00)])
        connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x01)])
    case .off:
        state.ancEnabled = false
        state.transparentHearingEnabled = false
        state.ancMode = .off

        connection.sendSet(for: .ancStatus, values: [.uint8(0x00)])
        connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
    }
}
```

**Step 5: Remove old `setUnifiedSliderValue`**

Delete lines 304-342 (the `setUnifiedSliderValue` method and its doc comment).

**Step 6: Build to verify**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`

Expected: Build will fail because `ANCControlView` still references `setUnifiedSliderValue` — that's expected and fixed in Task 3.

**Step 7: Commit**

```bash
git add MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift
git commit -m "refactor: split slider commands into handleSliderDragging + commitSliderValue with zone-change detection"
```

---

### Task 2: Redesign UnifiedANCSlider gesture and labels

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/UnifiedANCSlider.swift` (full rewrite)

**Step 1: Replace the full file content**

```swift
import SwiftUI

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
                        .onEnded { _ in
                            guard !isDisabled else { return }
                            onCommit?(value)
                        }
                )
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
```

**Step 2: Build to verify (will still fail due to ANCControlView)**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`

Expected: Compile error in `ANCControlView.swift` referencing old API — fixed in Task 3.

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/UnifiedANCSlider.swift
git commit -m "refactor: redesign slider with onDragging/onCommit split, detent feedback, centered labels"
```

---

### Task 3: Update ANCControlView call site

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/ANCControlView.swift:52-57`

**Step 1: Replace the slider instantiation**

Change lines 52-57 from:

```swift
UnifiedANCSlider(
    value: $sliderValue,
    isDisabled: viewModel.state.adaptiveModeEnabled
) { newValue in
    viewModel.setUnifiedSliderValue(newValue)
}
```

to:

```swift
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
```

**Step 2: Build to verify everything compiles**

Run: `cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/ANCControlView.swift
git commit -m "wire up slider onDragging/onCommit callbacks in ANCControlView"
```

---

### Task 4: Run tests and verify

**Files:**
- No changes — verification only

**Step 1: Run the test suite**

Run: `cd MomentumControl && xcodebuild test -project MomentumControl.xcodeproj -scheme MomentumControl 2>&1 | tail -20`

Expected: All tests pass. (Existing tests cover GAIAPacket, GAIAValueParser, GAIAPropertyRegistry — none test the slider directly, so no test failures expected.)

**Step 2: Final commit if any fixups needed**

If tests reveal issues, fix and commit with descriptive message.
