import Foundation

/// Active Noise Cancellation mode
enum ANCMode: Int, CaseIterable, Identifiable {
    case off = 0
    case anc = 1
    case transparency = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .anc: "ANC"
        case .transparency: "Transparency"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "speaker.wave.1"
        case .anc: "ear"
        case .transparency: "waveform"
        }
    }
}
