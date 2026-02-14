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

    /// Called by IOBluetooth on an internal thread when any device connects system-wide.
    /// Dispatches to main thread for thread-safe state mutation.
    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.handleDeviceConnected(device)
        }
    }

    private func handleDeviceConnected(_ device: IOBluetoothDevice) {
        guard let name = device.name else { return }

        let isSennheiser = name.localizedCaseInsensitiveContains("sennheiser") ||
                           name.localizedCaseInsensitiveContains("momentum")

        guard isSennheiser else { return }

        // Don't double-connect if we're already tracking a device
        if trackedDevice != nil {
            logger.info("Ignoring connect for \(name) -- already tracking a device")
            return
        }

        guard let address = device.addressString else {
            logger.warning("Sennheiser device has no address, skipping: \(name)")
            return
        }

        logger.info("Sennheiser device connected: \(name) (\(address))")

        trackedDevice = device

        // Register for disconnect on this specific device
        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )

        onDeviceConnected?(name, address)
    }

    /// Called by IOBluetooth on an internal thread when the tracked device disconnects.
    /// Dispatches to main thread for thread-safe state mutation.
    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.handleDeviceDisconnected(device)
        }
    }

    private func handleDeviceDisconnected(_ device: IOBluetoothDevice) {
        logger.info("Sennheiser device disconnected: \(device.name ?? "unknown")")

        disconnectNotification?.unregister()
        disconnectNotification = nil
        trackedDevice = nil

        onDeviceDisconnected?()
    }
}
