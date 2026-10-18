#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// One transcript row (WP-43 spec, section 7; plan Q35): a grey bubble for a person or a bot, or a centred line for
    /// room activity.
    struct RoomRowView: View {
        let row: RoomRow
        let chat: RoomChatModel

        private static let bubbleShape = RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)

        var body: some View {
            switch row {
            case .user(_, let text, _):
                VStack(alignment: .leading, spacing: 4) {
                    Text("You")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                    Text(text)
                        .font(HermesFont.bubble)
                        .padding(12)
                        .background(HermesColor.incomingBubble, in: Self.bubbleShape)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .member(_, let memberID, let text, _, let createdAt):
                HStack(alignment: .top, spacing: 8) {
                    RoomAvatarView(
                        name: chat.label(forMember: memberID), profile: chat.profile(forMember: memberID), size: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(chat.label(forMember: memberID))
                                .font(HermesFont.caption.weight(.semibold))
                                .foregroundStyle(HermesColor.accent)
                            Text(Date(timeIntervalSince1970: createdAt), style: .relative)
                                .font(HermesFont.caption2)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                        MarkdownView(text: text)
                            .padding(12)
                            .background(HermesColor.incomingBubble, in: Self.bubbleShape)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .activity(_, let text):
                Text(text)
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// A bot's monogram on its tint. The default profile, Hermes, is violet (WP-43 spec, section 7).
    struct RoomAvatarView: View {
        let name: String
        let profile: String?
        var size: CGFloat = 24

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Self.fill(forProfile: profile))
                Text(Self.monogram(for: name))
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(HermesColor.onAccent)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }

        /// Desktop's tint: hue from the profile name, saturation 68 percent, lightness 58 percent, as HSB for SwiftUI.
        static func fill(forProfile profile: String?) -> Color {
            guard let hue = RoomAvatarTint.hue(forProfile: profile ?? "") else {
                return Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)
            }
            return Color(hue: Double(hue) / 360, saturation: 0.66, brightness: 0.87)
        }

        static func monogram(for name: String) -> String {
            name.first.map { String($0).uppercased() } ?? "?"
        }
    }
#endif
