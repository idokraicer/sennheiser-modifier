import Foundation
import IOBluetooth
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

    /// True between enabling transparency mode and sending the intended level.
    /// This avoids a race where the headset briefly jumps to its default
    /// transparency level before our target value lands.
    private var isAwaitingTransparencyActivation = false

    /// Delay after enabling transparency before sending the target level.
    private static let transparencyActivationDelay: Duration = .milliseconds(150)

    /// Debounce drag updates to avoid flooding the headset with level changes.
    private static let sliderDebounceDelay: Duration = .seconds(0.3)

    /// Repeating heartbeat that pings the device and detects zombie RFCOMM channels.
    private var heartbeatTask: Task<Void, Never>?

    /// Timestamp of the last GAIA response received. Used by the heartbeat
    /// to decide whether a connection has gone silent (zombie channel).
    private var lastReceivedTime: Date = .distantPast

    /// True when the user clicked Disconnect (suppresses auto-reconnect).
    private var isUserInitiatedDisconnect = false

    /// Address of the most recently connected device, used for auto-reconnect.
    /// Persists across `state.reset()` so we can recover from unexpected drops.
    private var lastConnectedAddress: String?

    /// Pending auto-reconnect task — cancelled when the user explicitly disconnects.
    private var autoReconnectTask: Task<Void, Never>?

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
                guard let self else { return }
                self.lastReceivedTime = Date()
                self.handlePropertyUpdate(property: property, values: values)
            }
        }

        connection.onDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logger.info("Transport disconnected")
                self.lastSentZone = nil
                self.transparencyDebounceTask?.cancel()
                self.isAwaitingTransparencyActivation = false
                self.heartbeatTask?.cancel()
                self.heartbeatTask = nil

                let wasUserInitiated = self.isUserInitiatedDisconnect
                let addressToReconnect = self.lastConnectedAddress
                self.isUserInitiatedDisconnect = false


                self.state.reset()

                guard !wasUserInitiated, let address = addressToReconnect else { return }
                self.scheduleAutoReconnect(to: address, after: 2.0)
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
                self.transparencyDebounceTask?.cancel()
                self.isAwaitingTransparencyActivation = false
                // BT device fully gone — don't bother trying to auto-reconnect.
                // The monitor's onDeviceConnected will handle re-attachment when
                // the device comes back.
                self.lastConnectedAddress = nil
                self.autoReconnectTask?.cancel()
                self.autoReconnectTask = nil
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
                // Clear transitional flags once real state confirms the outcome
                if connStatus == 1 {
                    state.connectingDevices.remove(index)
                }
                if connStatus == 0 {
                    state.disconnectingDevices.remove(index)
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
        autoReconnectTask?.cancel()
        autoReconnectTask = nil

        state.connectionStatus = .connecting
        state.deviceAddress = address

        do {
            try await connection.connect(to: address)
            state.connectionStatus = .connected
            lastConnectedAddress = address
            lastReceivedTime = Date()
            requestAllProperties()
            startHeartbeat()
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
        isUserInitiatedDisconnect = true
        lastConnectedAddress = nil
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connection.disconnect()
        lastSentZone = nil
        state.reset()
    }

    // MARK: - Auto-Reconnect & Heartbeat

    /// Schedule an auto-reconnect attempt. Skips if the underlying Bluetooth
    /// device is no longer connected (BluetoothMonitor will handle that case).
    private func scheduleAutoReconnect(to address: String, after delay: TimeInterval) {
        autoReconnectTask?.cancel()
        autoReconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            guard !self.connection.isConnected else { return }

            // Only auto-reconnect if the BT device is still connected at the
            // system level — otherwise we'd just produce a flurry of failures.
            guard let device = IOBluetoothDevice(addressString: address),
                  device.isConnected() else {
                self.logger.info("Auto-reconnect skipped: BT device \(address) not connected")
                return
            }

            self.logger.info("Auto-reconnecting to \(address)")
            await self.connect(to: address)
        }
    }

    /// Periodically pings the device and forces a reconnect if responses stop arriving.
    /// Catches zombie RFCOMM channels where writes succeed but the device is unreachable.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                guard self.connection.isConnected else { return }

                self.connection.sendGet(for: .batteryPercent)

                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }

                let elapsed = Date().timeIntervalSince(self.lastReceivedTime)
                if elapsed > 45 {
                    self.logger.warning("Heartbeat: no response in \(Int(elapsed))s — forcing reconnect")
                    // Drop the zombie channel; onDisconnected handler will auto-reconnect.
                    self.connection.disconnect()
                    return
                }
            }
        }
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
        let didChangeZone = zone != lastSentZone

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
        if didChangeZone {
            lastSentZone = zone
            switch zone {
            case .anc:
                isAwaitingTransparencyActivation = false
                connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
            case .transparency:
                // Only enable transparency — do NOT send ANC_Status=0.
                // The device treats ANC_Status SET 0 as "turn off all noise control",
                // which forces off mode. The device auto-disables ANC when TH is enabled.
                isAwaitingTransparencyActivation = true
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x01)])
            case .off:
                break
            }
        }

        scheduleTransparencyLevelSend(
            transparencyLevel,
            mode: ANCTransparencyCommandPolicy.levelSendMode(
                zone: zone,
                didChangeZone: didChangeZone,
                isCommit: false,
                isAwaitingTransparencyActivation: isAwaitingTransparencyActivation
            )
        )
    }

    /// Called on drag end. Sends definitive transparency level; only sends mode commands if zone wasn't already set during drag.
    func commitSliderValue(_ value: Double) {
        let zone = zoneForSliderValue(value)
        let transparencyLevel = Int(value) // Direct 1:1 mapping
        let didChangeZone = zone != lastSentZone

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
        if didChangeZone {
            lastSentZone = zone
            lastModeChangeTime = Date()
            switch zone {
            case .anc:
                isAwaitingTransparencyActivation = false
                connection.sendSet(for: .ancStatus, values: [.uint8(0x01)])
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x00)])
            case .transparency:
                isAwaitingTransparencyActivation = true
                connection.sendSet(for: .transparentHearingStatus, values: [.uint8(0x01)])
            case .off:
                break
            }
        }

        scheduleTransparencyLevelSend(
            transparencyLevel,
            mode: ANCTransparencyCommandPolicy.levelSendMode(
                zone: zone,
                didChangeZone: didChangeZone,
                isCommit: true,
                isAwaitingTransparencyActivation: isAwaitingTransparencyActivation
            )
        )
    }
 
    func setAdaptiveANC(enabled: Bool) {
        state.adaptiveModeEnabled = enabled
        lastModeChangeTime = Date()
        connection.sendSet(for: .anc, values: [.uint8(0x03), .uint8(enabled ? 0x01 : 0x00)])
        if enabled {
            state.ancEnabled = true
            state.transparentHearingEnabled = false
            state.ancMode = .anc
            isAwaitingTransparencyActivation = false
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
            transparencyDebounceTask?.cancel()
            isAwaitingTransparencyActivation = false
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

    // MARK: - Paired Devices

    func requestPairedDeviceInfo(index: UInt8) {
        connection.sendInvocation(for: .pairedDeviceInfo, parameters: [.uint8(index)])
    }

    func requestPairedDeviceConnectionStatus(index: UInt8) {
        connection.sendInvocation(for: .pairedDeviceConnectionStatus, parameters: [.uint8(index)])
    }

    /// Returns this Mac's Bluetooth name for identifying "self" in the paired device list.
    private var localBluetoothName: String? {
        IOBluetoothHostController.default()?.nameAsString()
    }

    func connectPairedDevice(index: UInt8) {
        let connectedDevices = state.pairedDevices.filter { $0.isConnected }

        // If 2 devices already connected, auto-disconnect the non-Mac one first
        if connectedDevices.count >= 2 {
            let macName = localBluetoothName
            // Find a connected device that is NOT this Mac and NOT the target
            if let deviceToDisconnect = connectedDevices.first(where: {
                $0.index != index && !$0.name.localizedCaseInsensitiveContains(macName ?? "")
            }) {
                state.disconnectingDevices.insert(deviceToDisconnect.index)
                state.connectingDevices.insert(index)
                connection.sendInvocation(for: .pairedDeviceDisconnect, parameters: [.uint8(deviceToDisconnect.index)])
                // Wait for disconnect to process, then connect target
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    connection.sendInvocation(for: .pairedDeviceConnect, parameters: [.uint8(index)])
                }
                scheduleTransitionTimeout(for: index)
                scheduleTransitionTimeout(for: deviceToDisconnect.index)
                return
            }
        }

        state.connectingDevices.insert(index)
        connection.sendInvocation(for: .pairedDeviceConnect, parameters: [.uint8(index)])
        scheduleTransitionTimeout(for: index)
    }

    func disconnectPairedDevice(index: UInt8) {
        state.disconnectingDevices.insert(index)
        connection.sendInvocation(for: .pairedDeviceDisconnect, parameters: [.uint8(index)])
        scheduleTransitionTimeout(for: index)
    }

    /// Safety net: clear any transitional flag after 10s in case the real state never arrives.
    private func scheduleTransitionTimeout(for index: UInt8) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            state.connectingDevices.remove(index)
            state.disconnectingDevices.remove(index)
        }
    }

    func refreshAllConnectionStatuses() {
        for device in state.pairedDevices {
            requestPairedDeviceConnectionStatus(index: device.index)
        }
    }

    private func scheduleTransparencyLevelSend(_ transparencyLevel: Int, mode: ANCTransparencyLevelSendMode) {
        transparencyDebounceTask?.cancel()

        let sendLevel = { [self] in
            connection.sendSet(for: .ancTransparency, values: [.uint8(UInt8(clamping: transparencyLevel))])
            isAwaitingTransparencyActivation = false
        }

        switch mode {
        case .immediate:
            sendLevel()
        case .delayedForModeActivation:
            transparencyDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: Self.transparencyActivationDelay)
                guard !Task.isCancelled else { return }
                sendLevel()
            }
        case .debounced:
            transparencyDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: Self.sliderDebounceDelay)
                guard !Task.isCancelled else { return }
                sendLevel()
            }
        }
    }

    // MARK: - Scanner Access

    var bleScanner: BLEScanner { scanner }
}

enum ANCTransparencyLevelSendMode {
    case immediate
    case delayedForModeActivation
    case debounced
}

enum ANCTransparencyCommandPolicy {
    /// Determines when the slider should send its next transparency value.
    /// The unified slider only produces `.anc` and `.transparency`.
    static func levelSendMode(
        zone: ANCMode,
        didChangeZone: Bool,
        isCommit: Bool,
        isAwaitingTransparencyActivation: Bool
    ) -> ANCTransparencyLevelSendMode {
        assert(zone != .off, "Unified ANC slider should not route the .off zone through ANCTransparencyCommandPolicy")

        if isCommit {
            if zone == .transparency && (didChangeZone || isAwaitingTransparencyActivation) {
                return .delayedForModeActivation
            }
            return .immediate
        }

        if zone == .transparency && didChangeZone {
            return .delayedForModeActivation
        }

        return .debounced
    }
}
