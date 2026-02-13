import Foundation
import IOBluetooth
import os

/// Resolves a BLE peripheral UUID to a classic Bluetooth MAC address.
/// Uses IOBluetooth's paired device list or system_profiler as fallback.
enum MACResolver {
    private static let logger = Logger(subsystem: "com.momentumcontrol", category: "MACResolver")

    /// Attempt to resolve the MAC address for a BLE device by name
    static func resolve(deviceName: String) -> String? {
        // Try IOBluetooth paired device list first
        if let device = findInPairedDevices(name: deviceName) {
            logger.info("Resolved via IOBluetooth: \(device)")
            return device
        }

        // Fallback: system_profiler
        if let device = findViaSystemProfiler(name: deviceName) {
            logger.info("Resolved via system_profiler: \(device)")
            return device
        }

        logger.warning("Could not resolve MAC for: \(deviceName)")
        return nil
    }

    /// Search IOBluetooth paired devices by name
    private static func findInPairedDevices(name: String) -> String? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }

        for device in devices {
            if let deviceName = device.name,
               deviceName.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(deviceName) {
                return device.addressString
            }
        }

        return nil
    }

    /// Search system_profiler Bluetooth data for device by name
    private static func findViaSystemProfiler(name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("system_profiler failed: \(error.localizedDescription)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let btData = json["SPBluetoothDataType"] as? [[String: Any]] else {
            return nil
        }

        // Search through connected and previously connected devices
        for entry in btData {
            for key in ["device_connected", "device_not_connected"] {
                guard let devices = entry[key] as? [[String: Any]] else { continue }
                for deviceDict in devices {
                    for (deviceName, info) in deviceDict {
                        guard deviceName.localizedCaseInsensitiveContains(name) ||
                              name.localizedCaseInsensitiveContains(deviceName),
                              let infoDict = info as? [String: Any],
                              let address = infoDict["device_address"] as? String else { continue }
                        return address
                    }
                }
            }
        }

        return nil
    }

    /// List all paired Sennheiser devices
    static func listSennheiserDevices() -> [(name: String, address: String)] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return devices.compactMap { device in
            guard let name = device.name,
                  name.localizedCaseInsensitiveContains("sennheiser") ||
                  name.localizedCaseInsensitiveContains("momentum") else {
                return nil
            }
            return (name: name, address: device.addressString)
        }
    }
}
