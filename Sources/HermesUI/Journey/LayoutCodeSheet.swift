#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    /// Takes a layout code that someone shared and applies it to the graph (WP-52). The code is checked as it is typed
    /// or pasted, and Apply stays off until it is a good one.
    struct LayoutCodeSheet: View {
        let model: MemoryJourneyModel
        @Environment(\.dismiss) private var dismiss
        @State private var text = ""

        /// Why the text is not a usable code, or nil when it is one.
        private var problem: JourneyLayoutCode.Problem? {
            JourneyLayoutCode.problem(with: text)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("HJ1.\u{2026}", text: $text, axis: .vertical)
                            .font(HermesFont.code)
                            .lineLimit(3...8)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Layout code")
                            .accessibilityIdentifier("layoutCode.field")
                        Button("Paste from clipboard", systemImage: "doc.on.clipboard") { paste() }
                            .accessibilityIdentifier("layoutCode.paste")
                    } footer: {
                        footer
                    }
                }
                .navigationTitle("Apply layout code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("layoutCode.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { apply() }
                            .disabled(problem != nil)
                            .accessibilityIdentifier("layoutCode.apply")
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("layoutCode.sheet")
        }

        /// A hint at first, the reason once something is typed, and a go-ahead when the code is good.
        @ViewBuilder
        private var footer: some View {
            if text.isEmpty {
                Text("Paste a layout code from another device. It sets the filter, the timeline and the zoom.")
            } else if let problem {
                Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(HermesColor.destructive)
                    .accessibilityIdentifier("layoutCode.problem")
            } else {
                Label("This code works.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(HermesColor.statusConnected)
                    .accessibilityIdentifier("layoutCode.valid")
            }
        }

        private func paste() {
            if let pasted = UIPasteboard.general.string { text = pasted }
        }

        private func apply() {
            if model.applyLayoutCode(text) == nil { dismiss() }
        }
    }
#endif
