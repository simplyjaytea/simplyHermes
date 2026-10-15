#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// A reserved region the system reports in the view's coordinate space (the fold, or the inner camera).
    public struct ReservedRegionInfo: Sendable, Equatable, Identifiable {
        public var kind: String
        public var frame: CGRect
        public var isActive: Bool
        public var id: String { "\(kind)-\(frame.debugDescription)" }
    }

    /// Reads the real posture on an iPhone Duo and falls back to `.flat` everywhere else.
    ///
    /// The hinge comes from `UIHingeInteraction` (iOS 27.1). On older systems, regular iPhones and the iOS 27.0
    /// simulator there is no hinge, the posture stays `.flat`, and the shell lays out from the size class alone.
    @MainActor @Observable
    public final class DevicePostureMonitor {
        public private(set) var hinge: HingeReading?
        public private(set) var reservedRegions: [ReservedRegionInfo] = []
        /// Forces a posture (launch arguments, previews, tests). Wins over the hinge.
        public var override: DevicePosture?
        public var policy = PosturePolicy()

        public init(override: DevicePosture? = nil) {
            self.override = override
        }

        public var posture: DevicePosture { override ?? policy.posture(for: hinge) }

        func apply(hinge: HingeReading?) {
            if self.hinge != hinge { self.hinge = hinge }
        }

        func apply(regions: [ReservedRegionInfo]) {
            if reservedRegions != regions { reservedRegions = regions }
        }
    }

    extension View {
        /// Feeds the real device posture into `\.hermesPosture`. A forced posture on the monitor wins.
        public func hermesPostureSource(_ monitor: DevicePostureMonitor) -> some View {
            background { HingeObserverView(monitor: monitor).allowsHitTesting(false) }
                .environment(\.hermesPosture, monitor.posture)
        }
    }

    /// An invisible view that holds the hinge interaction and reads the reserved regions after each layout.
    struct HingeObserverView: UIViewRepresentable {
        let monitor: DevicePostureMonitor

        func makeUIView(context: Context) -> RegionProbeView {
            let view = RegionProbeView()
            view.isUserInteractionEnabled = false
            view.monitor = monitor
            if #available(iOS 27.1, *) {
                let interaction = UIHingeInteraction { [weak monitor] _, update in
                    let reading = update.hinge.flatMap { hinge in
                        HingeStatus(rawValue: Int(hinge.status.rawValue)).map {
                            HingeReading(status: $0, angleRadians: Double(hinge.angle))
                        }
                    }
                    monitor?.apply(hinge: reading)
                }
                view.addInteraction(interaction)
            }
            return view
        }

        func updateUIView(_ uiView: RegionProbeView, context: Context) {
            uiView.monitor = monitor
        }
    }

    final class RegionProbeView: UIView {
        weak var monitor: DevicePostureMonitor?

        override func layoutSubviews() {
            super.layoutSubviews()
            monitor?.apply(regions: Self.regions(in: window ?? self))
        }

        /// `UIView.reservedRegions(of:)` is refined for Swift and not importable by name. It is read through the
        /// Objective-C runtime so the app still builds and runs on systems without it.
        static func regions(in view: UIView) -> [ReservedRegionInfo] {
            let query = Selector(("reservedRegionsOfKind:options:"))
            guard view.responds(to: query), let kindType = NSClassFromString("UIViewReservedRegionKind") else {
                return []
            }
            var found: [ReservedRegionInfo] = []
            for (name, factory) in [("occlusion", "occlusionRegionKind"), ("division", "divisionRegionKind")] {
                let make = Selector((factory))
                guard (kindType as AnyObject).responds(to: make),
                    let kind = (kindType as AnyObject).perform(make)?.takeUnretainedValue()
                else { continue }
                // Options 1 includes inactive regions, so the debug view can show every region the system knows.
                typealias Query = @convention(c) (AnyObject, Selector, AnyObject, UInt) -> Unmanaged<NSArray>
                let call = unsafeBitCast(view.method(for: query), to: Query.self)
                let regions = call(view, query, kind, 1).takeUnretainedValue()
                for case let region as NSObject in regions {
                    let frame = (region.value(forKey: "frame") as? NSValue)?.cgRectValue ?? .zero
                    let active = (region.value(forKey: "active") as? Bool) ?? false
                    found.append(ReservedRegionInfo(kind: name, frame: frame, isActive: active))
                }
            }
            return found
        }
    }
#endif
