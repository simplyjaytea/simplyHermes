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
        /// Adds a Done button above the keyboard that closes it. Apply it once at the root of a form or sheet with text
        /// fields. The chat composers do not use it: they have a Hide keyboard button in their bottom row.
        func hermesKeyboardDoneButton() -> some View {
            toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { HermesKeyboard.dismiss() }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
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
