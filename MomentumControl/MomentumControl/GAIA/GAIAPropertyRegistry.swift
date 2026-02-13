import Foundation

/// Routes incoming GAIA response packets to the correct property definition.
/// Uses vendorID + commandID from the response to look up the matching property.
struct GAIAPropertyRegistry {
    /// Lookup key combining vendor and command IDs
    private struct ResponseKey: Hashable {
        let vendorID: UInt16
        let commandID: UInt16
    }

    /// Maps response vendor+command to (property, response type)
    private var responseMap: [ResponseKey: (GAIAPropertyDefinition, ResponseType)] = [:]

    enum ResponseType {
        case getValue      // GET response → parse with valueTypes
        case setResponse   // SET response → parse with valueTypes
        case invocationResult  // INVOCATION response → parse with resultTypes
        case notification  // Push notification → parse with valueTypes (same format as GET)
    }

    init(properties: [GAIAPropertyDefinition] = GAIAPropertyDefinition.allMVP) {
        for prop in properties {
            register(prop)
        }
    }

    mutating func register(_ property: GAIAPropertyDefinition) {
        // Register GET response
        if let vid = property.getResponseVendorID, let cid = property.getResponseCommandID {
            responseMap[ResponseKey(vendorID: vid, commandID: cid)] = (property, .getValue)
        }
        // Register SET response
        if let vid = property.setResponseVendorID, let cid = property.setResponseCommandID {
            responseMap[ResponseKey(vendorID: vid, commandID: cid)] = (property, .setResponse)
        }
        // Register INVOCATION response
        if let vid = property.invocationResponseVendorID, let cid = property.invocationResponseCommandID {
            responseMap[ResponseKey(vendorID: vid, commandID: cid)] = (property, .invocationResult)
        }
        // Register NOTIFICATION (push from device, same payload format as GET response)
        if let vid = property.notificationVendorID, let cid = property.notificationCommandID, cid != 0x0000 {
            responseMap[ResponseKey(vendorID: vid, commandID: cid)] = (property, .notification)
        }
    }

    /// Look up the property definition and response type for a given response packet
    func lookup(vendorID: UInt16, commandID: UInt16) -> (GAIAPropertyDefinition, ResponseType)? {
        responseMap[ResponseKey(vendorID: vendorID, commandID: commandID)]
    }

    /// Parse values from a response packet using the matched property definition
    func parseResponse(packet: GAIAPacket) -> (GAIAPropertyDefinition, [GAIAValue])? {
        guard let (property, responseType) = lookup(vendorID: packet.vendorID, commandID: packet.commandID) else {
            return nil
        }

        let values: [GAIAValue]
        switch responseType {
        case .getValue, .setResponse:
            values = property.parseGetResponse(payload: packet.payload)
        case .notification:
            // Notifications use valueTypes for GET/SET properties,
            // but fall back to resultTypes for invocation-only properties
            if !property.valueTypes.isEmpty {
                values = property.parseGetResponse(payload: packet.payload)
            } else {
                values = property.parseInvocationResult(payload: packet.payload)
            }
        case .invocationResult:
            values = property.parseInvocationResult(payload: packet.payload)
        }

        return (property, values)
    }
}
