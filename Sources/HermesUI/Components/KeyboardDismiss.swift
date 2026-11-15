#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Closing the software keyboard from code. The chat screens and the forms share it.
    enum HermesKeyboard {
        /// Asks whatever field has focus to give it up, which closes the keyboard.
        @MainActor
        static func dismiss() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    extension View {
        /// Lets a drag on a form or sheet with text fields close the keyboard. Apply it once at the root of the screen.
        /// The chat composers do not use it: they have a Hide keyboard button in their bottom row.
        ///
        /// It was a Done button on the keyboard's toolbar in alpha 5. Typing lagged on the device and the UI tests ran
        /// slow in that build, and the toolbar was a suspected cause, so the drag replaces it.
        func hermesKeyboardDismissOnScroll() -> some View {
            scrollDismissesKeyboard(.interactively)
        }
    }

    /// The Hide keyboard button of a chat's bottom row. It shows only while the keyboard is up, and keeps a 44 pt hit
    /// area.
    struct HideKeyboardButton: View {
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            if KeyboardWatcher.shared.isUp {
                Button {
                    HermesKeyboard.dismiss()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(HermesFont.body)
                        .foregroundStyle(palette.secondaryText)
                        .cappedSymbolSize()
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hermesPress)
                .accessibilityLabel(Text("Hide keyboard"))
                .accessibilityIdentifier("composer.hideKeyboard")
                .transition(.opacity)
            }
        }
    }

    /// A trailing row with the Hide keyboard button, for a composer that has no other row above it. It takes no room
    /// while the keyboard is down.
    struct HideKeyboardRow: View {
        var body: some View {
            if KeyboardWatcher.shared.isUp {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HideKeyboardButton()
                }
                .padding(.horizontal, 6)
            }
        }
    }
#endif
