import Foundation

/// Defines the command structure for a GAIA property operation
enum GAIAOperationType {
    case get
    case set
    case invocation
}

/// A data-driven definition of a GAIA property, replacing the C++ class hierarchy.
/// Each property knows its vendor/command IDs for GET, SET, and response routing.
struct GAIAPropertyDefinition: Sendable {
    let name: String

    // GET operation
    let getVendorID: UInt16?
    let getCommandID: UInt16?
    let getResponseVendorID: UInt16?
    let getResponseCommandID: UInt16?
    let valueTypes: [GAIAValueType]

    // SET operation
    let setVendorID: UInt16?
    let setCommandID: UInt16?
    let setResponseVendorID: UInt16?
    let setResponseCommandID: UInt16?
    let setTypes: [GAIAValueType]

    // INVOCATION operation
    let invocationVendorID: UInt16?
    let invocationCommandID: UInt16?
    let invocationResponseVendorID: UInt16?
    let invocationResponseCommandID: UInt16?
    let parameterTypes: [GAIAValueType]
    let resultTypes: [GAIAValueType]

    // NOTIFICATION (push from device, uses same payload format as GET response)
    let notificationVendorID: UInt16?
    let notificationCommandID: UInt16?

    init(
        name: String,
        getVendorID: UInt16? = nil, getCommandID: UInt16? = nil,
        getResponseVendorID: UInt16? = nil, getResponseCommandID: UInt16? = nil,
        valueTypes: [GAIAValueType] = [],
        setVendorID: UInt16? = nil, setCommandID: UInt16? = nil,
        setResponseVendorID: UInt16? = nil, setResponseCommandID: UInt16? = nil,
        setTypes: [GAIAValueType] = [],
        invocationVendorID: UInt16? = nil, invocationCommandID: UInt16? = nil,
        invocationResponseVendorID: UInt16? = nil, invocationResponseCommandID: UInt16? = nil,
        parameterTypes: [GAIAValueType] = [],
        resultTypes: [GAIAValueType] = [],
        notificationVendorID: UInt16? = nil, notificationCommandID: UInt16? = nil
    ) {
        self.name = name
        self.getVendorID = getVendorID
        self.getCommandID = getCommandID
        self.getResponseVendorID = getResponseVendorID
        self.getResponseCommandID = getResponseCommandID
        self.valueTypes = valueTypes
        self.setVendorID = setVendorID
        self.setCommandID = setCommandID
        self.setResponseVendorID = setResponseVendorID
        self.setResponseCommandID = setResponseCommandID
        self.setTypes = setTypes
        self.invocationVendorID = invocationVendorID
        self.invocationCommandID = invocationCommandID
        self.invocationResponseVendorID = invocationResponseVendorID
        self.invocationResponseCommandID = invocationResponseCommandID
        self.parameterTypes = parameterTypes
        self.resultTypes = resultTypes
        self.notificationVendorID = notificationVendorID
        self.notificationCommandID = notificationCommandID
    }

    /// Build a GET packet for this property
    func buildGetPacket() -> GAIAPacket? {
        guard let vid = getVendorID, let cid = getCommandID else { return nil }
        return .get(vendorID: vid, commandID: cid)
    }

    /// Build a SET packet for this property with the given values
    func buildSetPacket(values: [GAIAValue]) -> GAIAPacket? {
        guard let vid = setVendorID, let cid = setCommandID else { return nil }
        let payload = GAIAValueParser.encode(values: values)
        return .command(vendorID: vid, commandID: cid, payload: payload)
    }

    /// Build an INVOCATION packet for this property with the given parameters
    func buildInvocationPacket(parameters: [GAIAValue]) -> GAIAPacket? {
        guard let vid = invocationVendorID, let cid = invocationCommandID else { return nil }
        let payload = GAIAValueParser.encode(values: parameters)
        return .command(vendorID: vid, commandID: cid, payload: payload)
    }

    /// Parse response values from a packet's payload using valueTypes
    func parseGetResponse(payload: Data) -> [GAIAValue] {
        GAIAValueParser.parse(data: payload, types: valueTypes)
    }

    /// Parse response values from a SET response
    func parseSetResponse(payload: Data) -> [GAIAValue] {
        GAIAValueParser.parse(data: payload, types: valueTypes)
    }

    /// Parse result values from an INVOCATION response
    func parseInvocationResult(payload: Data) -> [GAIAValue] {
        GAIAValueParser.parse(data: payload, types: resultTypes)
    }
}

// MARK: - MVP Property Definitions

extension GAIAPropertyDefinition {

    // MARK: Battery

    static let batteryPercent = GAIAPropertyDefinition(
        name: "Battery_Percent",
        getVendorID: 0x0495, getCommandID: 0x0603,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x0703,
        valueTypes: [.uint8, .uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x0683
    )

    static let batteryChargingStatus = GAIAPropertyDefinition(
        name: "Battery_ChargingStatus",
        getVendorID: 0x0495, getCommandID: 0x0602,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x0702,
        valueTypes: [.uint8, .uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x0682
    )

    // MARK: ANC

    static let anc = GAIAPropertyDefinition(
        name: "ANC",
        getVendorID: 0x0495, getCommandID: 0x1A01,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1B01,
        valueTypes: [.uint8, .uint8, .uint8, .uint8, .uint8, .uint8],
        setVendorID: 0x0495, setCommandID: 0x1A00,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x1B00,
        setTypes: [.uint8, .uint8, .uint8, .uint8, .uint8, .uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x1A81
    )

    static let ancStatus = GAIAPropertyDefinition(
        name: "ANC_Status",
        getVendorID: 0x0495, getCommandID: 0x1A05,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1B05,
        valueTypes: [.uint8],
        setVendorID: 0x0495, setCommandID: 0x1A04,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x1B04,
        setTypes: [.uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x1A85
    )

    static let ancTransparency = GAIAPropertyDefinition(
        name: "ANC_Transparency",
        getVendorID: 0x0495, getCommandID: 0x1A03,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1B03,
        valueTypes: [.uint8],
        setVendorID: 0x0495, setCommandID: 0x1A02,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x1B02,
        setTypes: [.uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x1A83
    )

    // MARK: Transparent Hearing

    static let transparentHearing = GAIAPropertyDefinition(
        name: "TransparentHearing",
        getVendorID: 0x0495, getCommandID: 0x1803,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1903,
        valueTypes: [.uint8],
        setVendorID: 0x0495, setCommandID: 0x1802,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x1902,
        setTypes: [.uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x1883
    )

    static let transparentHearingStatus = GAIAPropertyDefinition(
        name: "TransparentHearing_Status",
        getVendorID: 0x0495, getCommandID: 0x1805,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1905,
        valueTypes: [.uint8],
        setVendorID: 0x0495, setCommandID: 0x1804,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x1904,
        setTypes: [.uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x1885
    )

    // MARK: Audio

    static let bassBoost = GAIAPropertyDefinition(
        name: "Setting_BassBoost",
        getVendorID: 0x0495, getCommandID: 0x1009,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1109,
        valueTypes: [.uint8],
        setVendorID: 0x0495, setCommandID: 0x1008,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x1108,
        setTypes: [.uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x1089
    )

    // MARK: Settings

    static let autoCall = GAIAPropertyDefinition(
        name: "Setting_AutoCall",
        getVendorID: 0x0495, getCommandID: 0x080B,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x090B,
        valueTypes: [.uint8],
        setVendorID: 0x0495, setCommandID: 0x080A,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x090A,
        setTypes: [.uint8]
    )

    static let comfortCall = GAIAPropertyDefinition(
        name: "Setting_ComfortCall",
        getVendorID: 0x0495, getCommandID: 0x0815,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x0915,
        valueTypes: [.uint8],
        setVendorID: 0x0495, setCommandID: 0x0814,
        setResponseVendorID: 0x0495, setResponseCommandID: 0x0914,
        setTypes: [.uint8]
    )

    // MARK: Device Info

    static let serialNumber = GAIAPropertyDefinition(
        name: "Core_SerialNumber",
        getVendorID: 0x001D, getCommandID: 0x0003,
        getResponseVendorID: 0x001D, getResponseCommandID: 0x0103,
        valueTypes: [.string]
    )

    static let firmwareVersion = GAIAPropertyDefinition(
        name: "Service_SystemReleaseVersion",
        getVendorID: 0x0495, getCommandID: 0x1201,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1301,
        valueTypes: [.uint16, .uint16, .uint16]
    )

    static let modelID = GAIAPropertyDefinition(
        name: "Versions_ModelId",
        getVendorID: 0x0495, getCommandID: 0x1206,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1306,
        valueTypes: [.string]
    )

    // MARK: Paired Devices

    static let pairedDevicesListSize = GAIAPropertyDefinition(
        name: "PairedDevicesListSize",
        getVendorID: 0x0495, getCommandID: 0x1400,
        getResponseVendorID: 0x0495, getResponseCommandID: 0x1500,
        valueTypes: [.uint16]
    )

    static let pairedDeviceInfo = GAIAPropertyDefinition(
        name: "PairedDevicesGetDeviceInfo",
        invocationVendorID: 0x0495, invocationCommandID: 0x1401,
        invocationResponseVendorID: 0x0495, invocationResponseCommandID: 0x1501,
        parameterTypes: [.uint8],
        resultTypes: [.uint8, .uint8, .uint8, .string]
    )

    static let pairedDeviceConnect = GAIAPropertyDefinition(
        name: "PairedDevicesConnectDevice",
        invocationVendorID: 0x0495, invocationCommandID: 0x1402,
        invocationResponseVendorID: 0x0495, invocationResponseCommandID: 0x1502,
        parameterTypes: [.uint8]
    )

    static let pairedDeviceDisconnect = GAIAPropertyDefinition(
        name: "PairedDevicesDisconnectDevice",
        invocationVendorID: 0x0495, invocationCommandID: 0x1403,
        invocationResponseVendorID: 0x0495, invocationResponseCommandID: 0x1503,
        parameterTypes: [.uint8]
    )

    static let pairedDeviceConnectionStatus = GAIAPropertyDefinition(
        name: "PairedDevicesGetConnectionStatus",
        invocationVendorID: 0x0495, invocationCommandID: 0x1404,
        invocationResponseVendorID: 0x0495, invocationResponseCommandID: 0x1504,
        parameterTypes: [.uint8],
        resultTypes: [.uint8, .uint8],
        notificationVendorID: 0x0495, notificationCommandID: 0x1484
    )

    // MARK: All MVP properties for iteration

    static let allMVP: [GAIAPropertyDefinition] = [
        .batteryPercent, .batteryChargingStatus,
        .anc, .ancStatus, .ancTransparency,
        .transparentHearing, .transparentHearingStatus,
        .bassBoost,
        .autoCall, .comfortCall,
        .serialNumber, .firmwareVersion, .modelID,
        .pairedDevicesListSize, .pairedDeviceInfo,
        .pairedDeviceConnect, .pairedDeviceDisconnect,
        .pairedDeviceConnectionStatus,
    ]
}
