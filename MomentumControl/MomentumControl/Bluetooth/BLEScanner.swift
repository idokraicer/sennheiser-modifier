import CoreBluetooth
import os

/// Discovered BLE device info
struct DiscoveredDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Scans for Sennheiser BLE devices using CoreBluetooth.
/// Devices advertise with service UUID 0000FCFE-0000-1000-8000-00805F9B34FB.
@Observable
final class BLEScanner: NSObject {
    private var centralManager: CBCentralManager?
    private let logger = Logger(subsystem: "com.momentumcontrol", category: "BLE")
    private let serviceUUID = CBUUID(string: Constants.sennheiserBLEServiceUUID)

    var discoveredDevices: [DiscoveredDevice] = []
    var isScanning = false
    var bluetoothState: CBManagerState = .unknown

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager?.state == .poweredOn else {
            logger.warning("Bluetooth not powered on (state: \(String(describing: self.centralManager?.state.rawValue)))")
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        centralManager?.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
        logger.info("Started BLE scan for Sennheiser devices")

        // Stop scan after 15 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            stopScan()
        }
    }

    func stopScan() {
        guard isScanning else { return }
        centralManager?.stopScan()
        isScanning = false
        logger.info("Stopped BLE scan")
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        logger.info("Bluetooth state: \(central.state.rawValue)")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )

        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)
            logger.info("Discovered: \(name) (UUID: \(peripheral.identifier))")
        }
    }
}
