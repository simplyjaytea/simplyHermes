#if canImport(UIKit)
    import SwiftUI

    /// Asks how old the ended sessions to prune must be, then confirms with a destructive alert (WP-40). The server keeps
    /// live and archived sessions.
    struct PruneSessionsSheet: View {
        let model: SessionsListModel
        @Environment(\.dismiss) private var dismiss
        /// Matches the server's `older_than_days` default.
        @State private var days = 90
        @State private var isConfirming = false
        @State private var isWorking = false

        private var dayText: String {
            days == 1 ? "1 day" : "\(days) days"
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Stepper(value: $days, in: 1...3650) {
                            Text("Older than \(dayText)")
                        }
                        .accessibilityIdentifier("prune.days")
                    } footer: {
                        Text(
                            "Ended sessions idle for longer than this are deleted from the server. "
                                + "Live sessions are never removed."
                        )
                    }
                }
                .navigationTitle("Prune old sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isWorking)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isWorking {
                            ProgressView()
                        } else {
                            Button("Prune…") { isConfirming = true }
                                .accessibilityIdentifier("prune.review")
                        }
                    }
                }
                .alert("Prune sessions older than \(dayText)?", isPresented: $isConfirming) {
                    Button("Prune", role: .destructive) { Task { await prune() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "Ended sessions are deleted from the server. Live sessions are never removed, "
                            + "and archived sessions are kept. This cannot be undone."
                    )
                }
            }
        }

        private func prune() async {
            isWorking = true
            defer { isWorking = false }
            if await model.prune(olderThanDays: days) { dismiss() }
        }
    }
#endif
