import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelUnavailableReason: Equatable, Sendable {
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedDevice

    var message: String {
        switch self {
        case .appleIntelligenceNotEnabled:
            return String(localized: "Apple Intelligence is turned off. Enable Apple Intelligence to use AFM.")
        case .modelNotReady:
            return String(localized: "Apple Foundation Model is not ready yet. Try again in a moment.")
        case .unsupportedDevice:
            return String(localized: "Apple Foundation Models are not supported on this device.")
        }
    }
}

struct AppleFoundationModelAvailabilityState: Equatable, Sendable {
    let isSupportedDevice: Bool
    let isAvailableNow: Bool
    let unavailableReason: AppleFoundationModelUnavailableReason?
}

enum AppleFoundationModelAvailability {
    static var current: AppleFoundationModelAvailabilityState {
        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS) || os(visionOS) || targetEnvironment(macCatalyst)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return AppleFoundationModelAvailabilityState(
                    isSupportedDevice: true,
                    isAvailableNow: true,
                    unavailableReason: nil
                )
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return AppleFoundationModelAvailabilityState(
                        isSupportedDevice: true,
                        isAvailableNow: false,
                        unavailableReason: .appleIntelligenceNotEnabled
                    )
                case .modelNotReady:
                    return AppleFoundationModelAvailabilityState(
                        isSupportedDevice: true,
                        isAvailableNow: false,
                        unavailableReason: .modelNotReady
                    )
                case .deviceNotEligible:
                    return AppleFoundationModelAvailabilityState(
                        isSupportedDevice: false,
                        isAvailableNow: false,
                        unavailableReason: .unsupportedDevice
                    )
                @unknown default:
                    return AppleFoundationModelAvailabilityState(
                        isSupportedDevice: false,
                        isAvailableNow: false,
                        unavailableReason: .unsupportedDevice
                    )
                }
            @unknown default:
                return AppleFoundationModelAvailabilityState(
                    isSupportedDevice: false,
                    isAvailableNow: false,
                    unavailableReason: .unsupportedDevice
                )
            }
        }
        #endif
        #endif

        return AppleFoundationModelAvailabilityState(
            isSupportedDevice: false,
            isAvailableNow: false,
            unavailableReason: .unsupportedDevice
        )
    }

    static var isSupportedDevice: Bool { current.isSupportedDevice }
    static var isAvailableNow: Bool { current.isAvailableNow }
    static var unavailableReason: AppleFoundationModelUnavailableReason? { current.unavailableReason }
}
