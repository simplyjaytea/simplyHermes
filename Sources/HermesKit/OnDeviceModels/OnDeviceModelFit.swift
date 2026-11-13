import Foundation

/// Whether a model fits this phone's memory, decided before the download (row 120, spec
/// Shared/simplyhermes-local-models-spec-2026-11-12.md). Two numbers: the device ceiling (the share of the phone's
/// memory iOS lets one app use) and what the app may allocate right now (`os_proc_available_memory()`). Both are
/// estimates, so only a model that can never fit is blocked.
public enum OnDeviceModelFit: Sendable, Equatable {
    /// Fits: as far as the app can tell, it will load.
    case fits
    /// Fits the phone, but not what is free right now. Downloading is allowed; loading may fail until memory frees up.
    case mayNotFit(availableBytes: Int64)
    /// Needs more than this phone lets one app use, whatever else is running. No download is offered.
    case tooBig(ceilingBytes: Int64)

    /// The share of the phone's memory one app can count on without the Increased Memory Limit entitlement. An
    /// estimate, not verified on the user's phone or on a sideloaded build (playbook section 6, question 4).
    public static let appShare = 0.55

    /// The device ceiling for `physicalMemory` bytes, or nil when the phone's memory is unknown (0).
    public static func ceiling(physicalMemory: UInt64) -> Int64? {
        guard physicalMemory > 0 else { return nil }
        return Int64(Double(physicalMemory) * appShare)
    }

    /// The fit of `model` on a phone with `physicalMemory` bytes, when the app may allocate `available` bytes now
    /// (nil when unknown). Unknown numbers never block.
    public static func assess(_ model: OnDeviceModel, physicalMemory: UInt64, available: Int64?) -> OnDeviceModelFit {
        let need = model.estimatedMemoryBytes
        if let ceiling = ceiling(physicalMemory: physicalMemory), need > ceiling {
            return .tooBig(ceilingBytes: ceiling)
        }
        if let available, need > available {
            return .mayNotFit(availableBytes: available)
        }
        return .fits
    }
}
