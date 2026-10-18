#if canImport(UIKit)
    import SwiftUI

    /// The first-use tips that have no single control to point at (plan Q51, decided as inline cards). Each one
    /// shows once, on the screen where its feature first appears.
    public enum InlineTipKind: String, CaseIterable, Sendable {
        case unfold
        case tent
        case shake

        var title: String {
            switch self {
            case .unfold: "Two columns"
            case .tent: "Glance view"
            case .shake: "Report a problem"
            }
        }

        var message: String {
            switch self {
            case .unfold: "Unfolded, your chats sit beside the open chat. Open a chat here to keep reading."
            case .tent: "Half-folded on the table, this view shows the current step with Stop, Deny and Approve."
            case .shake: "Shake the phone to send a bug report, with your screenshot and redacted diagnostics."
            }
        }

        var symbol: String {
            switch self {
            case .unfold: "rectangle.split.2x1"
            case .tent: "iphone.gen3.radiowaves.left.and.right"
            case .shake: "iphone.radiowaves.left.and.right"
            }
        }
    }

    /// Remembers which inline tips the user has seen. Turning tips off in Settings hides them all.
    public enum InlineTipStore {
        private static func key(_ kind: InlineTipKind) -> String { "tipSeen.\(kind.rawValue)" }

        /// True when the tip should appear now.
        public static func isPending(_ kind: InlineTipKind, defaults: UserDefaults = .standard) -> Bool {
            let tipsOn = defaults.object(forKey: HermesTips.key) as? Bool ?? true
            return tipsOn && !defaults.bool(forKey: key(kind))
        }

        /// Marks the tip as seen, so it does not appear again.
        public static func markSeen(_ kind: InlineTipKind, defaults: UserDefaults = .standard) {
            defaults.set(true, forKey: key(kind))
        }
    }

    /// A dismissible card for one inline tip. It stays for the rest of the visit even though it is marked seen.
    public struct InlineTipCard: View {
        let kind: InlineTipKind
        @State private var isShowing: Bool

        public init(kind: InlineTipKind) {
            self.kind = kind
            _isShowing = State(initialValue: InlineTipStore.isPending(kind))
        }

        public var body: some View {
            if isShowing {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: kind.symbol)
                        .font(.title3)
                        .foregroundStyle(HermesColor.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title).font(HermesFont.headline)
                        Text(kind.message)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HermesColor.secondaryText)
                            .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Dismiss tip"))
                }
                .padding(12)
                .background(
                    HermesColor.card, in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius, style: .continuous)
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tip.\(kind.rawValue)")
                .onAppear { InlineTipStore.markSeen(kind) }
                .transition(.opacity)
            }
        }

        private func dismiss() {
            InlineTipStore.markSeen(kind)
            withAnimation(HermesMotion.reducedFade) { isShowing = false }
        }
    }
#endif
