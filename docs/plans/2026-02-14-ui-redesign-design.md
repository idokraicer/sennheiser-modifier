# MomentumControl UI Redesign

**Date:** 2026-02-14
**Target:** MomentumControl macOS SwiftUI menu bar popover
**Direction:** macOS Control Center native feel + purposeful custom controls

## Design Principles

- Control Center tile language: `.ultraThinMaterial` cards, 16pt corners, SF Symbols
- Custom-drawn controls that visually reflect their function
- Progressive disclosure: essentials upfront, secondary features in expandable section
- Dynamic accent color that shifts with ANC mode
- Spring animations throughout for snappy-but-organic feel

## Color System

- System-adaptive light/dark mode (follows macOS)
- Dynamic accent shifts with ANC state:
  - **ANC:** Cool blue
  - **Adaptive:** Soft purple/teal
  - **Off:** Neutral gray
  - **Transparency:** Warm amber
- All other elements use system primary/secondary/tertiary colors

## Animation Defaults

- State transitions: `.spring(response: 0.35, dampingFraction: 0.8)`
- Color/waveform transitions: `.easeInOut(duration: 0.3)`
- Expand/collapse: `.easeInOut` with simultaneous slide + fade

## Popover Structure (320pt wide)

```
┌──────────────────────────────────┐
│  [🎧⟳] Device Name         72%  │  Header card
│                                  │
│  ┌─────── ANC Tile ───────────┐  │
│  │  ANC 80%       ⊜ Adaptive  │  │
│  │  ANC ━━●━━ Off ━━ Transp.  │  │
│  │  ⊜ Anti-Wind               │  │
│  └────────────────────────────┘  │
│                                  │
│  ⊜ Bass Boost                    │  Quick toggles
│                                  │
│  More                         ⌄  │  Expandable
│  ┌ Paired Devices (2) ───────┐  │
│  │ iPhone 15 Pro   ● Disconn │  │
│  │ MacBook Pro     ○ Connect  │  │
│  └────────────────────────────┘  │
│  ┌ Call Settings ─────────────┐  │
│  │ ⊜ Auto Answer  ⊜ Comfort  │  │
│  └────────────────────────────┘  │
│                                  │
│  Disconnect              Quit    │  Footer
└──────────────────────────────────┘
```

## Section 1: Device Header

Compact horizontal card with `.ultraThinMaterial` background.

- **Left:** SF Symbol headphone icon with a **circular battery ring** drawn around it using `Circle().trim()`. Ring fills proportionally to battery level. Color: green > orange > red. When charging, the ring pulses with a subtle glow animation.
- **Center:** Device name (`.headline`), firmware version (`.caption2`, secondary).
- **Right:** Battery percentage as bold monospaced number.

No separate battery bar — the ring replaces it.

## Section 2: ANC Control Tile

The hero element. Largest card in the popover with a colored glow halo behind it.

### Adaptive Toggle

Top-right of the card. Pill-shaped button labeled "Adaptive" with an SF Symbol.

- **Off:** Outlined, secondary color. Unified slider is interactive.
- **On:** Filled with purple/teal accent. Slider becomes dimmed (~40% opacity) and read-only. Label changes to "Adaptive ANC". No sub-controls appear. Tile glow shifts to purple/teal.

### Unified ANC Slider

Single horizontal slider with three labeled zones:

```
ANC ─────────── Off ─────────── Transparency
```

- Custom-drawn track with **waveform visualization**: tiny waveform bars drawn with SwiftUI `Path`. Waves compress/flatten toward ANC end, open up toward Transparency end. Neutral/dormant at Off center.
- **Accent color shifts continuously** along the track: cool blue (ANC) → gray (Off) → warm amber (Transparency). Thumb picks up this color.
- Card background gets a very faint tint matching current position.
- Glow halo behind card matches current accent color.

### Dynamic Label

Above the slider, `.caption` label shows current state: "ANC 80%" / "Off" / "Transparency 60%". Monospaced digits to prevent text jiggle.

### Conditional Sub-controls

- **Adaptive off, slider in ANC zone:** Anti-Wind pill toggle appears with spring slide-down animation.
- **Adaptive on:** No sub-controls (Adaptive manages wind automatically).
- **Slider in Off or Transparency zone:** No sub-controls.

Tile height animates smoothly as sub-controls appear/disappear.

## Section 3: Quick Toggles Row

Horizontal row of custom **pill-shaped toggle buttons**.

- **Bass Boost:** SF Symbol `speaker.wave.3` inside a capsule.
  - Off: outlined stroke, secondary color.
  - On: filled with accent, icon turns white, subtle scale-up spring animation.
- No section header — pills are self-explanatory.
- Row is left-aligned, designed to accommodate future additions.

## Section 4: Expandable "More" Section

Disclosure row: "More" label + chevron that rotates 180° on toggle.

### 4a: Paired Devices

- `.ultraThinMaterial` card with section label + count badge.
- Each device: name + connection status dot (green = connected, gray = not).
- Text button actions on the right: "Connect" or "Disconnect".
- Inline `ProgressView` while loading.

### 4b: Call Settings

- Two pill toggles in a row (same style as Bass Boost):
  - **Auto Answer:** `phone.arrow.up.right` icon
  - **Comfort Call:** `phone.circle` icon

Both sub-cards stack vertically with 8pt spacing. Expand/collapse animates with simultaneous slide-down and fade-in.

## Section 5: Footer Bar

Pinned at bottom, outside scroll area.

- **Left:** "Disconnect" text button (only when connected), secondary color.
- **Right:** "Quit" text button, secondary color.
- No divider — material background difference provides separation.

## Model Changes

- Remove `comfortModeEnabled` from `DeviceState` and related ViewModel methods.
- Adaptive mode becomes a primary mode concept rather than a sub-toggle.

## View File Structure

| File | Purpose |
|---|---|
| `PopoverContentView.swift` | Root layout, connected vs scanner routing |
| `DeviceHeaderView.swift` | Header card with battery ring |
| `ANCControlView.swift` | ANC tile: unified slider, adaptive toggle, anti-wind |
| `BatteryRingView.swift` | Custom `Circle().trim()` battery indicator (new) |
| `UnifiedANCSlider.swift` | Custom slider with waveform track (new) |
| `WaveformTrackShape.swift` | Path-drawn waveform visualization (new) |
| `PillToggle.swift` | Reusable custom pill toggle component (new) |
| `QuickTogglesView.swift` | Bass boost pills row |
| `ExpandableSection.swift` | Generic disclosure container (new) |
| `ConnectedDevicesView.swift` | Paired devices list |
| `SettingsView.swift` | Call settings pills |
| `DeviceScannerView.swift` | Disconnected state scanner |
| `MenuBarIcon.swift` | Menu bar icon + battery text |
