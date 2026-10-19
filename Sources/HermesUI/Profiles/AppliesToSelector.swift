#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The "Applies to" chip (WP-41): which profile a settings page edits. It follows the active profile by default and
    /// hides itself while the server has fewer than two profiles.
    ///
    /// It knows nothing about the page it sits on, so the settings pages that come later reuse it as they are.
    public struct AppliesToSelector: View {
        private let choice: AppliesTo
        private let profiles: [HermesProfile]
        private let active: String?
        private let onSelect: (AppliesTo) -> Void

        /// Creates the chip for `choice`, made under the `active` profile of `profiles`. `onSelect` gets the new choice.
        public init(
            choice: AppliesTo, profiles: [HermesProfile], active: String?, onSelect: @escaping (AppliesTo) -> Void
        ) {
            self.choice = choice
            self.profiles = profiles
            self.active = active
            self.onSelect = onSelect
        }

        public var body: some View {
            if AppliesTo.isShown(for: profiles) {
                Menu {
                    ForEach(choice.options(in: profiles, active: active)) { option in
                        Button {
                            onSelect(option.choice)
                        } label: {
                            if option.isSelected {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Applies to")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                        Text(chipTitle)
                            .font(HermesFont.subheadline.weight(.semibold))
                            .foregroundStyle(HermesColor.primaryText)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: HermesMetrics.minTapTarget)
                    .background(HermesColor.fill, in: Capsule())
                    .contentShape(Capsule())
                }
                .accessibilityLabel("Applies to: \(chipTitle)")
                .accessibilityHint("Chooses which profile the settings on this page edit")
                .accessibilityIdentifier("appliesToSelector")
            }
        }

        private var chipTitle: String {
            choice.chipTitle(in: profiles, active: active)
        }
    }
#endif
