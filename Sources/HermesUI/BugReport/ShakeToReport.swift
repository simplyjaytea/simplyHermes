#if canImport(UIKit)
    import Combine
    import SwiftUI
    import UIKit

    extension Notification.Name {
        /// Posted when the user shakes the phone. The object is the `UIWindow` that got the shake.
        public static let hermesDeviceShaken = Notification.Name("HermesDeviceShaken")
    }

    extension UIWindow {
        // Shake events travel up the responder chain to the window when no view handles them.
        override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake {
                NotificationCenter.default.post(name: .hermesDeviceShaken, object: self)
            }
            super.motionEnded(motion, with: event)
        }

        /// A PNG of what the window shows right now.
        func screenshotPNG() -> Data? {
            let renderer = UIGraphicsImageRenderer(bounds: bounds)
            let image = renderer.image { _ in
                drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
            return image.pngData()
        }
    }

    extension View {
        /// Runs `action` when the phone is shaken, with a screenshot of the shaken window.
        public func onDeviceShake(perform action: @escaping (_ screenshot: Data?) -> Void) -> some View {
            onReceive(NotificationCenter.default.publisher(for: .hermesDeviceShaken)) { notification in
                action((notification.object as? UIWindow)?.screenshotPNG())
            }
        }
    }
#endif
