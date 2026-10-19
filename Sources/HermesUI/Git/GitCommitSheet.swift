#if canImport(SwiftUI)
    import HermesKit
    import SwiftUI

    /// The commit form: the message, the recent subjects to reuse, and commit or commit and push. Commit and push
    /// confirms first, because the push leaves the server.
    struct GitCommitSheet: View {
        let model: GitReviewModel

        @Environment(\.dismiss) private var dismiss
        @State private var message = ""
        @State private var recent: [String] = []
        @State private var confirmingPush = false

        private var trimmed: String {
            message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section("Message") {
                        TextField("Commit message", text: $message, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    if !recent.isEmpty {
                        Section("Recent subjects") {
                            ForEach(recent, id: \.self) { subject in
                                Button(subject) { message = subject }
                            }
                        }
                    }
                    if let errorText = model.errorText {
                        Section {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button("Commit") { Task { await commit(push: false) } }
                            .disabled(trimmed.isEmpty || model.working)
                        Button("Commit and push") { confirmingPush = true }
                            .disabled(trimmed.isEmpty || model.working)
                    } footer: {
                        Text("With nothing staged, the server stages every change before it commits.")
                    }
                }
                .navigationTitle("Commit")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .task { recent = await model.commitContext()?.recentSubjects ?? [] }
                .confirmationDialog("Push after committing?", isPresented: $confirmingPush) {
                    Button("Commit and push") { Task { await commit(push: true) } }
                } message: {
                    Text("The commit goes to the branch's remote on the server.")
                }
            }
        }

        private func commit(push: Bool) async {
            if await model.commit(message: trimmed, push: push) {
                dismiss()
            }
        }
    }
#endif
