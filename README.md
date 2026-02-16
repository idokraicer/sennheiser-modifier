# MomentumControl

A macOS menu bar app for controlling Sennheiser Momentum 4 headphones over Bluetooth.

Communicates directly with the headphones using the GAIA v3 protocol over RFCOMM — no Sennheiser Smart Control app required.

## Features

- **ANC & Transparency Control** — Unified slider spanning ANC (noise cancellation) through Transparency mode with real-time adjustment
- **Adaptive ANC** — Toggle adaptive noise cancellation
- **Anti-Wind** — Toggle wind noise reduction
- **Bass Boost** — Enable/disable bass enhancement
- **Battery Monitoring** — Live battery percentage with charging status indicator
- **On-Head Detection** — Toggle automatic pause/play when headphones are removed
- **Call Settings** — Auto-answer and comfort call toggles
- **Paired Devices** — View and manage Bluetooth connections from your headphones' paired device list
- **Auto-Connect** — Automatically detects and connects to your headphones when they're available
- **Menu Bar Native** — Lives in your macOS menu bar, accessible with a single click

## Requirements

- macOS 14.0 (Sonoma) or later
- Sennheiser Momentum 4 headphones paired via Bluetooth

## Installation

### Quick Install (no Xcode needed)

Run this in Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/idokraicer/sennheiser-modifier/main/install.sh)"
```

This downloads the latest pre-built release, installs to `/Applications`, and launches the app.

### Build from Source

Requires Xcode 16.0+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. **Clone and build:**

   ```bash
   git clone https://github.com/idokraicer/sennheiser-modifier.git
   cd sennheiser-modifier
   ./build.sh
   ```

2. **Install the built app:**

   ```bash
   cp -R build/Build/Products/Release/MomentumControl.app /Applications/
   ```

   Or open in Xcode:
   ```bash
   cd MomentumControl
   xcodegen generate
   open MomentumControl.xcodeproj
   ```

### Bluetooth Permissions

On first launch, macOS will ask for Bluetooth permission. MomentumControl needs this to communicate with your headphones over RFCOMM.

## Usage

1. **Pair your headphones** with your Mac through macOS Bluetooth settings (if not already paired).
2. **Launch MomentumControl** — it appears as a headphones icon in the menu bar.
3. **Click the menu bar icon** to open the control panel.
4. The app will **auto-connect** to your Sennheiser Momentum 4 if they're available. You can also manually select a device from the list.

### ANC Slider

The unified slider covers the full noise control spectrum:
- **Left side (0–50%)** — Active Noise Cancellation, from maximum ANC at the left edge to minimal ANC at center
- **Right side (50–100%)** — Transparency mode, from minimal transparency at center to maximum transparency at the right edge

## Architecture

```
UI (SwiftUI Menu Bar Views)
  ↕
ViewModel (HeadphoneViewModel)
  ↕
GAIA Protocol (GAIAConnection)
  ↕
Property Registry (routes vendor+command IDs to property handlers)
  ↕
Bluetooth Transport (RFCOMM channel)
  ↕
IOBluetooth (macOS native Bluetooth)
```

The app communicates using the **GAIA v3 protocol**, a binary protocol used by Qualcomm-based audio devices. Packets follow the format:

```
[0xFF 0x03] [length:2B] [vendorID:2B] [commandID:2B] [payload...]
```

### Key Source Files

| Layer | File | Purpose |
|---|---|---|
| App entry | `App/MomentumControlApp.swift` | Menu bar app entry point |
| ViewModel | `ViewModel/HeadphoneViewModel.swift` | Bridges GAIA protocol to UI state |
| Protocol | `GAIA/GAIAConnection.swift` | Packet routing and transport orchestration |
| Packets | `GAIA/GAIAPacket.swift` | GAIA v3 packet encoding/decoding |
| Properties | `GAIA/GAIAPropertyRegistry.swift` | Maps vendor+command IDs to property handlers |
| State | `Model/DeviceState.swift` | Observable state container for all device properties |
| Transport | `Bluetooth/RFCOMMChannel.swift` | IOBluetooth RFCOMM wrapper |
| Constants | `Utilities/Constants.swift` | Protocol constants and vendor IDs |

All source code lives under `MomentumControl/MomentumControl/`.

## Running Tests

```bash
cd MomentumControl
xcodegen generate  # if not already done
xcodebuild test -project MomentumControl.xcodeproj -scheme MomentumControl
```

Tests cover GAIA packet encoding/decoding, value parsing, and property registry routing.

## Compatibility

This app is built for the **Sennheiser Momentum 4**. It may work with other Sennheiser/Qualcomm GAIA-based headphones, but this has not been tested. The property definitions in `Model/m4.json` are specific to the Momentum 4.

## Acknowledgments

- Protocol knowledge derived from reverse-engineering the Sennheiser Smart Control Android app and the [sennheiser-desktop-client](https://github.com/zaval/sennheiser-desktop-client) project by [@zaval](https://github.com/zaval).
- GAIA v3 is a Qualcomm protocol used in many Bluetooth audio devices.

## License

[MIT](LICENSE)
