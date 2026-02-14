# Bluetooth Auto-Detection Design

## Problem

The app only checks for Sennheiser devices at launch or via manual scan. If headphones connect after the app is already running, the user must restart or manually trigger a scan.

## Solution

Use `IOBluetoothDevice.register(forConnectNotifications:selector:)` to monitor for Bluetooth Classic device connections system-wide. Filter for Sennheiser/Momentum devices by name and auto-connect via RFCOMM.

## Approach

**Approach A** (selected): Event-driven monitoring via IOBluetooth notification registration. Zero polling, zero battery cost, immediate detection.

Rejected alternatives:
- **Polling paired devices on a timer** — wasteful, introduces latency
- **Distributed NSNotifications** — undocumented, unreliable across macOS versions

## Design

### New Component: `BluetoothMonitor`

Location: `MomentumControl/Bluetooth/BluetoothMonitor.swift`

An `NSObject` subclass that:
1. On init, registers for system-wide BT connect notifications
2. Filters incoming connections for "sennheiser" or "momentum" in the device name
3. Fires `onDeviceConnected(name: String, address: String)` callback
4. Registers per-device disconnect notification on the connected device
5. Fires `onDeviceDisconnected()` on disconnect, resumes monitoring

### Integration with HeadphoneViewModel

- ViewModel owns a `BluetoothMonitor` instance
- `onDeviceConnected` triggers `connect(to: address)` (existing RFCOMM flow)
- `onDeviceDisconnected` triggers `state.reset()` and monitor keeps watching
- Existing `autoConnect()` stays as launch-time fallback for already-connected devices
- While already connected, further connect notifications are ignored

### Lifecycle

- Monitor starts at app launch (ViewModel init)
- Active for entire app lifetime (menu bar app)
- Unregisters on deinit
- Guards against double-connection
