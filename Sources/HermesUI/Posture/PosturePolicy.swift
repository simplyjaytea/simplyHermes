#if canImport(UIKit)
    import Foundation

    /// The state of the hinge as the system reports it (`UIHinge.Status`, iOS 27.1).
    public enum HingeStatus: Int, Sendable, CaseIterable {
        case unknown = 0
        case closed = 1
        case partiallyOpen = 2
        case fullyOpen = 3
    }

    /// One hinge reading: the discrete status plus the angle the system reports, in radians.
    public struct HingeReading: Sendable, Equatable {
        public var status: HingeStatus
        public var angleRadians: Double

        public init(status: HingeStatus, angleRadians: Double) {
            self.status = status
            self.angleRadians = angleRadians
        }

        public var angleDegrees: Double { angleRadians * 180 / .pi }
    }

    /// Turns a hinge reading into the posture the shell lays out for.
    ///
    /// The system reports `closed`, `partiallyOpen` and `fullyOpen` plus an angle. It does not name "half-fold" or
    /// "tent", so this policy decides: a partly open hinge is half-fold, and a tightly folded one is tent.
    /// `tentMaxDegrees` is a guess until JT calibrates it on a real device with the debug view.
    public struct PosturePolicy: Sendable, Equatable {
        /// A partly open hinge at or below this angle counts as tent (an upside-down V standing on the table).
        public var tentMaxDegrees: Double = 75

        public init() {}

        public func posture(for hinge: HingeReading?) -> DevicePosture {
            guard let hinge, hinge.status == .partiallyOpen else { return .flat }
            // The tolerance absorbs the radians-to-degrees rounding, so exactly 75° counts as tent.
            return hinge.angleDegrees <= tentMaxDegrees + 1e-6 ? .tent : .halfFolded
        }
    }
#endif
