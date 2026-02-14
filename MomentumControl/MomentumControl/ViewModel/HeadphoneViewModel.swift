import Foundation
import os

/// Bridges GAIAConnection ↔ DeviceState ↔ UI.
/// Handles response → state mapping, user action → command sending,
/// and the transparency slider debounce.
@Observable
final class HeadphoneViewModel {
    let state: DeviceState
    private let connection: GAIAConnection
    private let scanner: BLEScanner
    private let monitor: BluetoothMonitor
    private let logger = Logger(subsystem: "com.momentumcontrol", category: "ViewModel")

    /// Debounce task for transparency slider
    private var transparencyDebounceTask: Task<Void, Never>?

    /// Tracks the last ANC zone sent to the headset to avoid redundant mode-switch commands.
    private var lastSentZone: ANCMode?

    /// Timestamp of last user-initiated mode change, used to suppress stale re-fetch responses.
    private var lastModeChangeTime: Date = .distantPast

    /// Debounce task for unknown-command re-fetch (prevents cascading GETs).
    private var unknownRefetchTask: Task<Void, Never>?

    init(transport: BluetoothTransport? = nil) {
        self.state = DeviceState()
        self.scanner = BLEScanner()
        self.monitor = BluetoothMonitor()

        let actualTransport = transport ?? RFCOMMChannel()
        self.connection = GAIAConnection(transport: actualTransport)

        setupResponseHandler()
        setupBluetoothMonitor()
    }

    // MARK: - Response Handling

    private func setupResponseHandler() {
        connection.onPropertyReceived = { [weak self] property, values in
            Task { @MainActor in
                self?.handlePropertyUpdate(property: property, values: values)
            }
        }

        connection.onDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logger.info("Device disconnected unexpectedly")
                self.lastSentZone = nil
                self.state.reset()
            }
        }

        connection.onUnknownPacket = { [weak self] vendorID, commandID, _ in
            guard let self, vendorID == Constants.sennheiserVendorID else { return }
            logger.info("Unknown Sennheiser cmd=\(String(format: "0x%04X", commandID))")
            Task { @MainActor in
                self.debouncedRefetchANCState()
            }
        }
    }

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
                self.lastSentZone = nil
                if self.connection.isConnected {
                    self.connection.disconnect()
                } else {
                    self.state.reset()
                }
            }
        }
    }

    @MainActor
    private func handlePropertyUpdate(property: GAIAPropertyDefinition, values: [GAIAValue]) {
        logger.info("Property update: \(property.name) = \(values)")

        switch property.name {
        case "Battery_Percent":
            if values.count >= 2 {
                state.batterySource = values[0].asUInt8 ?? 0
                state.batteryPercent = Int(values[1].asUInt8 ?? 0)
            } else if values.count == 1 {
                // Real device sends only 1 byte (the percent)
                state.batteryPercent = Int(values[0].asUInt8 ?? 0)
            }

        case "Battery_ChargingStatus":
            if values.count >= 2 {
                state.isCharging = (values[1].asUInt8 ?? 0) != 0
            } else if values.count == 1 {
                state.isCharging = (values[0].asUInt8 ?? 0) != 0
            }

        case "ANC":
            // 6 UINT8 values: [mode, antiWind, idx, comfort, idx, adaptive]
            if values.count >= 6 {
                let antiWind = values[1].asInt
                state.antiWindEnabled = antiWind == 1 || antiWind == 2
                state.antiWindValue = antiWind
                state.adaptiveModeEnabled = values[5].asInt == 1
            }

        case "ANC_Status":
            if let v = values.first?.asUInt8 {
                // During user-initiated mode changes, the slider already set the flags.
                // Don't let device responses overwrite them — they can arrive out-of-order
                // (e.g. ANC_Status=0 arrives before TransparentHearing_Status=1, causing a
                // brief "off" state).
                guard !isInModeChangeCooldown else { break }
                state.ancEnabled = v == 0x01
                updateANCMode()
            }

        case "ANC_Transparency":
            if let v = values.first?.asUInt8 {
                state.ancTransparencyLevel = Int(v)
            }

        case "TransparentHearing":
            // This is the transparent hearing level/value, NOT the on/off status.
            // Don't set transparentHearingEnabled from this — only TransparentHearing_Status controls that.
            break

        case "TransparentHearing_Status":
            if let v = values.first?.asUInt8 {
                guard !isInModeChangeCooldown else { break }
                state.transparentHearingEnabled = v == 0x01
                updateANCMode()
            }

        case "Setting_BassBoost":
            if let v = values.first?.asUInt8 {
                state.bassBoostEnabled = v == 0x01
            }

        case "Setting_AutoCall":
            if let v = values.first?.asUInt8 {
                state.autoCallEnabled = v == 0x01
            }

        case "Setting_ComfortCall":
            if let v = values.first?.asUInt8 {
                state.comfortCallEnabled = v == 0x01
            }

        case "Core_SerialNumber":
            state.serialNumber = values.first?.asString

        case "Service_SystemReleaseVersion":
            if values.count >= 3 {
                let major = values[0].asUInt16 ?? 0
                let minor = values[1].asUInt16 ?? 0
                let patch = values[2].asUInt16 ?? 0
                state.firmwareVersion = "\(major).\(minor).\(patch)"
            }

        case "Versions_ModelId":
            if let model = values.first?.asString {
                state.modelID = model
                state.deviceName = model
            }

        case "PairedDevicesListSize":
            if let count = values.first?.asUInt16 {
                state.pairedDeviceCount = Int(count)
                // Request info for each paired device
                for i in 0..<Int(count) {
                    requestPairedDeviceInfo(index: UInt8(i))
                }
            }

        case "PairedDevicesGetDeviceInfo":
            if values.count >= 4,
               let index = values[0].asUInt8,
               let deviceType = values[2].asUInt8,
               let name = values[3].asString {
                let device = PairedDevice(
                    index: index,
                    connectionState: 0,  // Will be updated by GetConnectionStatus
                    deviceType: deviceType,
                    name: name
                )
                // Update or append
                if let existing = state.pairedDevices.firstIndex(where: { $0.index == index }) {
                    state.pairedDevices[existing] = device
                } else {
                    state.pairedDevices.append(device)
                }
                state.pairedDevices.sort { $0.index < $1.index }
                // Request actual connection status for this device
                requestPairedDeviceConnectionStatus(index: index)
            }

        case "PairedDevicesGetConnectionStatus":
            // Response: [deviceIndex, connectionStatus]
            // connectionStatus: 0 = not connected, 1 = connected
            if values.count >= 2,
               let index = values[0].asUInt8,
               let connStatus = values[1].asUInt8 {
                if let existing = state.pairedDevices.firstIndex(where: { $0.index == index }) {
                    let old = state.pairedDevices[existing]
                    state.pairedDevices[existing] = PairedDevice(
                        index: old.index,
                        connectionState: connStatus,
                        deviceType: old.deviceType,
                        name: old.name
                    )
                }
            }

        case "PairedDevicesConnectDevice", "PairedDevicesDisconnectDevice":
            // Refresh at multiple intervals — headphones need time to complete state change
            for delay in [0.5, 2.0, 5.0] {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    refreshAllConnectionStatuses()
                }
            }

        default:
            logger.debug("Unhandled property: \(property.name)")
        }
    }

    /// Whether we're within the cooldown period after a user-initiated mode change.
    private var isInModeChangeCooldown: Bool {
        Date().timeIntervalSince(lastModeChangeTime) <= 3.0
    }

    private func updateANCMode() {
        let oldMode = state.ancMode
        if state.transparentHearingEnabled {
            state.ancMode = .transparency
        } else if state.ancEnabled {
            state.ancMode = .anc
        } else {
            state.ancMode = .off
        }
        if state.ancMode != oldMode {
            let newMode = state.ancMode
            let anc = state.ancEnabled
            let th = state.transparentHearingEnabled
            let cd = isInModeChangeCooldown
            logger.info("ancMode: \(String(describing: oldMode)) → \(String(describing: newMode)) anc=\(anc) th=\(th) cooldown=\(cd)")
        }
    }

    /// Debounced re-fetch of ANC state after unknown commands.
    /// Skips if user recently changed mode (device returns stale GET responses during transitions).
    /// Only re-fetches ancTransparency and anc — status GETs are unreliable and we rely on
    /// push notifications for ANC_Status/TransparentHearing_Status instead.
    @MainActor
    private func debouncedRefetchANCState() {
        // Suppress re-fetch during cooldown after user-initiated mode changes
        guard Date().timeIntervalSince(lastModeChangeTime) > 3.0 else {
            logger.info("Suppressing re-fetch: within user-action cooldown")
            return
        }

        // Debounce: multiple unknown commands in quick succession → single re-fetch
        unknownRefetchTask?.cancel()
        unknownRefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            // Only re-fetch properties whose GETs return reliable data.
            // ANC_Status and TransparentHearing_Status GETs return 0 during
            // transitions, which incorrectly flips the UI to "Off".
            connection.sendGet(for: .ancTransparency)
            connection.sendGet(for: .anc)
        }
    }

    // MARK: - Connection

    func connect(to address: String) async {
        state.connectionStatus = .connecting
        state.deviceAddress = address

        do {
            try await connection.connect(to: address)
            state.connectionStatus = .connected
            requestAllProperties()
        } catch {
            state.connectionStatus = .error(error.localizedDescription)
            logger.error("Connection failed: \(error.localizedDescription)")
        }
    }

    /// Try to connect to a known Sennheiser device from paired list
    func autoConnect() async {
        let devices = MACResolver.listSennheiserDevices()
        if let first = devices.first {
            logger.info("Auto-connecting to \(first.name) at \(first.address)")
            state.deviceName = first.name
            await connect(to: first.address)
        } else {
            state.connectionStatus = .disconnected
        }
    }

    func disconnect() {
        connection.disconnect()
        lastSentZone = nil
        state.reset()
    }

    // MARK: - Request All Properties

    func requestAllProperties() {
        // Register for push notifications from the headphones
        registerNotifications()

        connection.sendGet(for: .batteryPercent)
        connection.sendGet(for: .batteryChargingStatus)
        connection.sendGet(for: .ancStatus)
        connection.sendGet(for: .anc)
        connection.sendGet(for: .ancTransparency)
        connection.sendGet(for: .transparentHearingStatus)
        connection.sendGet(for: .bassBoost)
        connection.sendGet(for: .autoCall)
        connection.sendGet(for: .comfortCall)
        connection.sendGet(for: .serialNumber)
        connection.sendGet(for: .firmwareVersion)
        connection.sendGet(for: .modelID)
        connection.sendGet(for: .pairedDevicesListSize)
    }

    /// Register for push notifications so the headphones proactively send state changes.
    /// Feature group IDs from m4.json — sent as UINT8 parameter to command 0x0007.
    private func registerNotifications() {
        let featureGroups: [(name: String, vendorID: UInt16, groupID: UInt8)] = [
            ("core",                0x0495, 0),
            ("Device",              0x0495, 2),
            ("battery",             0x0495, 3),
            ("genericAudio",        0x0495, 4),
            ("userEQ",              0x0495, 8),
            ("versions",            0x0495, 9),
            ("deviceManagement",    0x0495, 10),
            ("mmi",                 0x0495, 11),
            ("transparentHearing",  0x0495, 12),
            ("ANC",                 0x0495, 13),
        ]

        for group in featureGroups {
            let packet = GAIAPacket.command(
                vendorID: group.vendorID,
                commandID: 0x0007,
                payload: Data([group.groupID])
            )
            logger.info("Registering notification: \(group.name) (group \(group.groupID))")
            connection.send(packet)
        }
    }

    // MARK: - User Actions

    func setAntiWind(enabled: Bool) {
        // ANC SET uses sub-property format: [index, value]
        connection.sendSet(for: .anc, values: [.uint8(0x01), .uint8(enabled ? 0x01 : 0x00)])
    }

    func setAntiWindValue(_ value: Int) {
        connection.sendSet(for: .anc, values: [.uint8(0x01), .uint8(UInt8(clamping: value))])
    }

    /// Human-readable label for the current unified slider position.
    func unifiedSliderLabel(for value: Double) -> String {
        if value <= 50 {
            let pct = Int((1.0 - value / 50.0) * 100)
            return "ANC \(pct)%"
        } else {
            let pct = Int((value - 50.0) / 50.0 * 100)
            return "Transparency \(pct)%"
        }
    }

    /// Whether the slider is in the ANC zone (for showing sub-controls).
    func isInANCZone(value: Double) -> Bool {
        value <= 50
    }

    /// Derive the ANC zone from a unified slider value.
    private func zoneForSliderValue(_ value: Double) -> ANCMode {
        if value <= 50 { return .anc }
        return .transparency
    }

    /// Called on every drag frame. Updates state for UI, sends Bluetooth commands only on zone change or debounced ANC level.
    func handleSliderDragging(_ value: Double) {
        let zone = zoneForSliderValue(value)
        let transparencyLevel = Int(value) // Direct 1:1 mapping: slider 0-100 = device 0-100

        // Keep cooldown active while user is dragging (prevents device
        // notifications from overwriting slider-set state mid-drag)
        lastModeChangeTime = Date()

        // Always update state for UI responsiveness
        switch zone {
        case .anc:
            state.ancEnabled = true
            state.transparentHearingEnabled = false
            state.ancTransparencyLevel = transparencyLevel
            state.ancMode = .anc
        case .transparency:
            state.ancEnabled = false
            state.transparentHearingEnabled = true
            state.ancTransparencyLevel = transparencyLevel
            state.ancMode = .transparency
        case .off:
            break // Slider never produces off zone
        }

        // Only send mode-switch commands when zone actually changes
        if zone != lastSentZone {
            lastSentZone = zone
            switch zone {
            case .anc:
                connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
            case .transparency:
                // Only enable transparency — do NOT send ANC_Status=0.
                // The device treats ANC_Status SET 0 as "turn off all noise control",
                // which forces off mode. The device auto-disables ANC when TH is enabled.
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x01)])
            case .off:
                break
            }
        }

        // Debounce ANC transparency level
        transparencyDebounceTask?.cancel()
        transparencyDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            connection.sendSet(for: .ancTransparency, values: [.uint8(UInt8(clamping: transparencyLevel))])
        }
    }

    /// Called on drag end. Sends definitive transparency level; only sends mode commands if zone wasn't already set during drag.
    func commitSliderValue(_ value: Double) {
        let zone = zoneForSliderValue(value)
        let transparencyLevel = Int(value) // Direct 1:1 mapping

        // Ensure cooldown lasts 3 seconds from drag release (not from last zone change)
        lastModeChangeTime = Date()

        // Update state
        switch zone {
        case .anc:
            state.ancEnabled = true
            state.transparentHearingEnabled = false
            state.ancTransparencyLevel = transparencyLevel
            state.ancMode = .anc
        case .transparency:
            state.ancEnabled = false
            state.transparentHearingEnabled = true
            state.ancTransparencyLevel = transparencyLevel
            state.ancMode = .transparency
        case .off:
            break // Slider never produces off zone
        }

        // Only send mode-switch if zone changed since last drag frame
        // (handleSliderDragging already sent mode commands during drag;
        // re-sending here can cause the headphones to reset ANC_Transparency)
        if zone != lastSentZone {
            lastSentZone = zone
            lastModeChangeTime = Date()
            switch zone {
            case .anc:
                connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
            case .transparency:
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x01)])
            case .off:
                break
            }
        }

        // Always send the definitive transparency level
        transparencyDebounceTask?.cancel()
        connection.sendSet(for: .ancTransparency, values: [.uint8(UInt8(clamping: transparencyLevel))])
    }

    func setAdaptiveANC(enabled: Bool) {
        state.adaptiveModeEnabled = enabled
        lastModeChangeTime = Date()
        connection.sendSet(for: .anc, values: [.uint8(0x03), .uint8(enabled ? 0x01 : 0x00)])
        if enabled {
            state.ancEnabled = true
            state.transparentHearingEnabled = false
            state.ancMode = .anc
            connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
            connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
        }
    }

    /// Turn noise control off (both ANC and Transparent Hearing disabled) or re-enable at last known level.
    func setOff(enabled: Bool) {
        if enabled {
            state.ancEnabled = false
            state.transparentHearingEnabled = false
            state.adaptiveModeEnabled = false
            state.ancMode = .off
            lastSentZone = nil
            lastModeChangeTime = Date()
            connection.sendSet(for: .ancStatus, values: [.uint8(0x00)])
            connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
        } else {
            // Re-enable by reusing the proven slider commit path.
            // Reset lastSentZone so mode-switch commands are sent.
            lastSentZone = nil
            commitSliderValue(Double(state.ancTransparencyLevel))
        }
    }

    func setBassBoost(enabled: Bool) {
        connection.sendSet(for: .bassBoost, values: [.uint8(enabled ? 0x01 : 0x00)])
    }

    func setAutoCall(enabled: Bool) {
        connection.sendSet(for: .autoCall, values: [.uint8(enabled ? 0x01 : 0x00)])
        // Re-fetch after SET since device sends empty ACK
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            connection.sendGet(for: .autoCall)
        }
    }

    func setComfortCall(enabled: Bool) {
        connection.sendSet(for: .comfortCall, values: [.uint8(enabled ? 0x01 : 0x00)])
        // Re-fetch after SET since device sends empty ACK
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            connection.sendGet(for: .comfortCall)
        }
    }

    // MARK: - Paired Devices

    func requestPairedDeviceInfo(index: UInt8) {
        connection.sendInvocation(for: .pairedDeviceInfo, parameters: [.uint8(index)])
    }

    func requestPairedDeviceConnectionStatus(index: UInt8) {
        connection.sendInvocation(for: .pairedDeviceConnectionStatus, parameters: [.uint8(index)])
    }

    func connectPairedDevice(index: UInt8) {
        connection.sendInvocation(for: .pairedDeviceConnect, parameters: [.uint8(index)])
    }

    func disconnectPairedDevice(index: UInt8) {
        connection.sendInvocation(for: .pairedDeviceDisconnect, parameters: [.uint8(index)])
    }

    func refreshAllConnectionStatuses() {
        for device in state.pairedDevices {
            requestPairedDeviceConnectionStatus(index: device.index)
        }
    }

    // MARK: - Scanner Access

    var bleScanner: BLEScanner { scanner }
}
