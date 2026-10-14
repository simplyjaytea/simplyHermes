#if canImport(UIKit)
    import SwiftUI

    /// A capsule chip for quick actions, filters and the model picker.
    public struct HermesChip: View {
        private let title: String
        private let systemImage: String?
        private let isSelected: Bool
        private let action: () -> Void

        @State private var tapCount = 0

        public init(
            _ title: String,
            systemImage: String? = nil,
            isSelected: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.isSelected = isSelected
            self.action = action
        }

        public var body: some View {
            Button {
                tapCount += 1
                action()
            } label: {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
                .font(HermesFont.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(isSelected ? HermesColor.onAccent : HermesColor.primaryText)
                .background(isSelected ? HermesColor.accent : HermesColor.fill, in: Capsule())
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .hermesFeedback(.selection, trigger: tapCount)
        }
    }
#endif
