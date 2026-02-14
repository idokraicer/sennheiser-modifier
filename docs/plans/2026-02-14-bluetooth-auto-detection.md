# Bluetooth Auto-Detection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-detect when a paired Sennheiser device connects to macOS and silently open a GAIA RFCOMM connection, with auto-reset on disconnect.

**Architecture:** New `BluetoothMonitor` class uses `IOBluetoothDevice.register(forConnectNotifications:selector:)` to listen for system-wide BT connections, filters for Sennheiser/Momentum devices by name, and fires callbacks. `HeadphoneViewModel` owns the monitor and wires connect/disconnect events to existing RFCOMM flow.

**Tech Stack:** Swift 5.10, IOBluetooth framework, macOS 14.0+

---

### Task 1: Create `BluetoothMonitor` class

**Files:**
- Create: `MomentumControl/MomentumControl/Bluetooth/BluetoothMonitor.swift`

**Step 1: Create BluetoothMonitor**

```swift
import Foundation
import IOBluetooth
import os

/// Monitors system-wide Bluetooth Classic connections and fires callbacks
/// when a Sennheiser/Momentum device connects or disconnects.
final class BluetoothMonitor: NSObject {
    private let logger = Logger(subsystem: "com.momentumcontrol", category: "BluetoothMonitor")

    /// Held to keep the system-wide connect notification alive
    private var connectNotification: IOBluetoothUserNotification?

    /// Held to track disconnect of the currently-connected device
    private var disconnectNotification: IOBluetoothUserNotification?

    /// The device we're currently tracking (to avoid double-connect)
    private var trackedDevice: IOBluetoothDevice?

    var onDeviceConnected: ((_ name: String, _ address: String) -> Void)?
    var onDeviceDisconnected: (() -> Void)?

    override init() {
        super.init()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        logger.info("Started monitoring for Bluetooth connections")
    }

    func stopMonitoring() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotification?.unregister()
        disconnectNotification = nil
        trackedDevice = nil
        logger.info("Stopped monitoring for Bluetooth connections")
    }

    /// Called by IOBluetooth when any device connects system-wide
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let name = device.name else { return }

        let isSennheiser = name.localizedCaseInsensitiveContains("sennheiser") ||
                           name.localizedCaseInsensitiveContains("momentum")

        guard isSennheiser else { return }

        // Don't double-connect if we're already tracking a device
        if trackedDevice != nil {
            logger.info("Ignoring connect for \(name) — already tracking a device")
            return
        }

        logger.info("Sennheiser device connected: \(name) (\(device.addressString ?? "unknown"))")

        trackedDevice = device

        // Register for disconnect on this specific device
        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )

        if let address = device.addressString {
            onDeviceConnected?(name, address)
        }
    }

    /// Called when the tracked device disconnects
    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        logger.info("Sennheiser device disconnected: \(device.name ?? "unknown")")

        disconnectNotification?.unregister()
        disconnectNotification = nil
        trackedDevice = nil

        onDeviceDisconnected?()
    }
}
```

**Step 2: Verify it compiles**

Run:
```bash
cd MomentumControl && xcodegen generate && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Bluetooth/BluetoothMonitor.swift
git commit -m "feat: add BluetoothMonitor for system-wide device detection"
```

---

### Task 2: Integrate BluetoothMonitor into HeadphoneViewModel

**Files:**
- Modify: `MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift`

**Step 1: Add monitor property and wire callbacks**

In `HeadphoneViewModel`, add a `BluetoothMonitor` property alongside the existing `scanner`, and wire up its callbacks in `init()`:

```swift
// Add property (next to `private let scanner: BLEScanner`)
private let monitor: BluetoothMonitor

// In init(), after self.scanner = BLEScanner():
self.monitor = BluetoothMonitor()

// After setupResponseHandler(), add:
setupBluetoothMonitor()
```

Add the setup method:

```swift
private func setupBluetoothMonitor() {
    monitor.onDeviceConnected = { [weak self] name, address in
        Task { @MainActor in
            guard let self else { return }
            // Don't reconnect if already connected
            guard !self.connection.isConnected else {
                self.logger.info("Monitor: ignoring connect, already connected")
                return
            }
            self.logger.info("Monitor: auto-connecting to \(name) at \(address)")
            self.state.deviceName = name
            await self.connect(to: address)
        }
    }

    monitor.onDeviceDisconnected = { [weak self] in
        Task { @MainActor in
            guard let self else { return }
            self.logger.info("Monitor: device disconnected, resetting state")
            self.connection.disconnect()
            self.state.reset()
        }
    }
}
```

**Step 2: Verify it compiles**

Run:
```bash
cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/ViewModel/HeadphoneViewModel.swift
git commit -m "feat: wire BluetoothMonitor into ViewModel for auto-connect/disconnect"
```

---

### Task 3: Update DeviceScannerView to show monitoring status

**Files:**
- Modify: `MomentumControl/MomentumControl/Views/DeviceScannerView.swift`

**Step 1: Add monitoring indicator**

Replace the static "Disconnected" text with a "Monitoring for devices..." indicator when disconnected, so the user knows the app is actively watching. Keep the existing "Known Devices" list and "Scan" button as fallback options.

Add a monitoring status indicator below the hero icon section:

```swift
// After the hero icon VStack, before "Known Devices" section:
if viewModel.state.connectionStatus == .disconnected {
    HStack(spacing: 6) {
        ProgressView()
            .controlSize(.small)
        Text("Monitoring for devices...")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**Step 2: Verify it compiles**

Run:
```bash
cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add MomentumControl/MomentumControl/Views/DeviceScannerView.swift
git commit -m "feat: show monitoring indicator in scanner view"
```

---

### Task 4: Run full build and manual test

**Step 1: Full clean build**

Run:
```bash
cd MomentumControl && xcodebuild -project MomentumControl.xcodeproj -scheme MomentumControl -configuration Debug clean build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

**Step 2: Run tests**

Run:
```bash
cd MomentumControl && xcodebuild test -project MomentumControl.xcodeproj -scheme MomentumControl 2>&1 | tail -10
```
Expected: All tests pass

**Step 3: Final commit (if any fixups needed)**

Only if changes were made to fix build/test issues.
