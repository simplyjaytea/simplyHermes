#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A bot's face: its emoji, its SF Symbol, or the automatic monogram, on its tint (plan Q33).
    struct BotAvatarView: View {
        let name: String
        let avatar: BotAvatar?
        let tint: String
        var size: CGFloat = 44

        var body: some View {
            ZStack {
                Circle().fill(Self.color(named: tint))
                face
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }

        @ViewBuilder
        private var face: some View {
            switch avatar {
            case .emoji(let emoji)?:
                Text(emoji).font(.system(size: size * 0.5))
            case .symbol(let symbol)?:
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            case nil:
                Text(BotMonogram.text(for: name))
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }

        /// The names in `BotTint.palette` as system colours.
        static func color(named name: String) -> Color {
            switch name {
            case "blue": .blue
            case "teal": .teal
            case "indigo": .indigo
            case "purple": .purple
            case "pink": .pink
            case "orange": .orange
            case "green": .green
            default: .gray
            }
        }
    }

    /// The avatar choices: the automatic monogram first, then `BotAvatarChoices` emoji and symbols.
    struct AvatarPicker: View {
        @Binding var avatar: BotAvatar?
        let name: String
        let tint: String

        var body: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                choice(nil)
                ForEach(BotAvatarChoices.emoji, id: \.self) { emoji in
                    choice(.emoji(emoji))
                }
                ForEach(BotAvatarChoices.symbols, id: \.self) { symbol in
                    choice(.symbol(symbol))
                }
            }
            .padding(.vertical, 4)
        }

        private func choice(_ value: BotAvatar?) -> some View {
            Button {
                avatar = value
            } label: {
                BotAvatarView(name: name, avatar: value, tint: tint, size: 40)
                    .overlay {
                        if avatar == value {
                            Circle().strokeBorder(HermesColor.accent, lineWidth: 3)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.label(for: value))
            .accessibilityAddTraits(avatar == value ? .isSelected : [])
        }

        private static func label(for value: BotAvatar?) -> String {
            switch value {
            case .emoji(let emoji)?: "Emoji \(emoji)"
            case .symbol(let symbol)?: "Symbol \(symbol)"
            case nil: "Monogram"
            }
        }
    }
#endif
