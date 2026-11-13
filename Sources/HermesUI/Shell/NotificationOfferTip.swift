#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI
    import UserNotifications

    /// The in-chat offer "Get a notification when Hermes finishes?" (spec section 4). ``NotificationOffer`` decides
    /// when; this asks iOS for permission only when the user taps Turn on.
    @MainActor @Observable
    public final class NotificationOfferModel {
        public static let shared = NotificationOfferModel()

        public private(set) var isOffering = false
        @ObservationIgnored private let defaults: UserDefaults

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        /// A turn ran long or reached an approval while the app was in use.
        public func noteLongTurn() {
            Task {
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                var offer = NotificationOffer.load(from: defaults)
                let show = offer.noteLongTurn(permissionUndecided: status == .notDetermined)
                offer.save(to: defaults)
                if show { isOffering = true }
            }
        }

        func turnOn() {
            isOffering = false
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        }

        func notNow() {
            isOffering = false
            var offer = NotificationOffer.load(from: defaults)
            offer.dismiss()
            offer.save(to: defaults)
        }
    }

    /// Shown above a chat's composer when ``NotificationOfferModel`` offers. It never covers the composer and never
    /// takes focus.
    public struct NotificationOfferTip: View {
        @Bindable private var model: NotificationOfferModel
        @Environment(\.hermesPalette) private var palette

        public init(model: NotificationOfferModel = .shared) {
            self.model = model
        }

        public var body: some View {
            if model.isOffering {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Get a notification when Hermes finishes? You can leave the app while it works.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.primaryText)
                    HStack(spacing: 8) {
                        Button("Turn on") { model.turnOn() }
                            .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                            .accessibilityIdentifier("notificationOffer.turnOn")
                        Button("Not now") { model.notNow() }
                            .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                            .accessibilityIdentifier("notificationOffer.notNow")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 12)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notificationOffer")
            }
        }
    }
#endif
