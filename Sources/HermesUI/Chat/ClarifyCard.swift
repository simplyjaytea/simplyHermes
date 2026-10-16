#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The agent's questions as an inline form in a grey bubble (plan Q25). Choice questions show buttons, others a
    /// text field. Send is enabled once every question has an answer.
    struct ClarifyCard: View {
        let item: LiveChatModel.PendingClarify
        let onSend: ([String: String]) -> Void
        @State private var picks: [String: Set<String>] = [:]
        @State private var typed: [String: String] = [:]

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label("Hermes has a question", systemImage: "questionmark.bubble")
                    .font(HermesFont.subheadline.weight(.semibold))
                ForEach(item.questions, id: \.qid) { question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.question).font(HermesFont.bubble)
                        if let choices = question.choices, !choices.isEmpty {
                            ForEach(choices, id: \.self) { choice in
                                choiceRow(question, choice)
                            }
                        } else {
                            TextField("Your answer", text: binding(for: question.qid), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                Button("Send") { onSend(answers()) }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .disabled(!isComplete)
                    .accessibilityIdentifier("clarify.send")
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 12)
            .background(
                HermesColor.incomingBubble,
                in: RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
            )
            .bubbleRow(.leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("clarify.card")
        }

        private func choiceRow(_ question: ClarifyQuestion, _ choice: String) -> some View {
            let selected = picks[question.qid, default: []].contains(choice)
            return Button {
                toggle(question, choice)
            } label: {
                HStack {
                    Image(
                        systemName: selected
                            ? (question.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                            : (question.multiSelect ? "square" : "circle")
                    )
                    .foregroundStyle(selected ? HermesColor.accent : HermesColor.secondaryText)
                    Text(choice).font(HermesFont.body).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: HermesMetrics.minTapTarget - 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }

        private func toggle(_ question: ClarifyQuestion, _ choice: String) {
            var current = picks[question.qid, default: []]
            if question.multiSelect {
                if current.contains(choice) { current.remove(choice) } else { current.insert(choice) }
            } else {
                current = [choice]
            }
            picks[question.qid] = current
        }

        private func binding(for qid: String) -> Binding<String> {
            Binding(get: { typed[qid, default: ""] }, set: { typed[qid] = $0 })
        }

        private func answers() -> [String: String] {
            var result: [String: String] = [:]
            for question in item.questions {
                if let choices = question.choices, !choices.isEmpty {
                    // In the order the server listed them, so a multi-select answer is stable.
                    let chosen = choices.filter { picks[question.qid, default: []].contains($0) }
                    result[question.qid] = chosen.joined(separator: ", ")
                } else {
                    result[question.qid] = typed[question.qid, default: ""].trimmingCharacters(
                        in: .whitespacesAndNewlines)
                }
            }
            return result
        }

        private var isComplete: Bool {
            answers().values.allSatisfy { !$0.isEmpty }
        }
    }

    /// A sheet with a secure field for a sudo password or a secret value (plan Q25). The text is held only while the
    /// sheet is open and goes to the server on Send.
    struct SecureValueSheet: View {
        let item: LiveChatModel.PendingValue
        let onSend: (String) -> Void
        let onCancel: () -> Void
        @State private var value = ""
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        SecureField("Value", text: $value)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("secret.field")
                    } header: {
                        if let detail = item.detail { Text(detail) }
                    } footer: {
                        Text("It goes to your Hermes server and is not saved on this phone.")
                    }
                }
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            onSend(value)
                            value = ""
                            dismiss()
                        }
                        .disabled(value.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
        }
    }
#endif
