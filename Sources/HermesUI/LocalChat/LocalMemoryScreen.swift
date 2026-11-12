#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI

    /// The memory list's state. Every change keeps the last ``LocalMemoryChange`` so the screen can offer Undo.
    @MainActor
    @Observable
    final class LocalMemoryListModel {
        private(set) var memories: [LocalMemory] = []
        private(set) var lastChange: LocalMemoryChange?
        private(set) var problem: String?
        @ObservationIgnored private let store: any LocalMemoryStore

        init(store: any LocalMemoryStore) {
            self.store = store
        }

        func load() async {
            memories = (try? await store.memories()) ?? []
        }

        /// Returns false, with ``problem`` set, when the text is blank or too long.
        func add(_ text: String) async -> Bool {
            await run {
                let saved = try await store.save(text, source: .user, at: Date())
                lastChange = .saved(saved)
            }
        }

        func edit(_ memory: LocalMemory, to text: String) async -> Bool {
            await run { try await store.update(memory.id, text: text) }
        }

        func togglePin(_ memory: LocalMemory) async {
            _ = await run { try await store.setPinned(memory.id, !memory.isPinned) }
        }

        func delete(_ memory: LocalMemory) async {
            _ = await run {
                try await store.delete(memory.id)
                lastChange = .deleted(memory)
            }
        }

        func deleteAll() async {
            _ = await run {
                // Undo restores what was really deleted, not this screen's possibly older copy (review m1).
                lastChange = .deletedAll(try await store.deleteAll())
            }
        }

        func undo() async {
            guard let change = lastChange else { return }
            lastChange = nil
            _ = await run { try await change.undo(in: store) }
        }

        func dismissUndo() {
            lastChange = nil
        }

        private func run(_ work: () async throws -> Void) async -> Bool {
            defer { Task { await load() } }
            do {
                try await work()
                problem = nil
                return true
            } catch LocalMemoryError.empty {
                problem = "Write something to remember."
            } catch LocalMemoryError.tooLong {
                problem = "Keep a memory under \(LocalMemoryRules.itemLimit) characters."
            } catch {
                problem = "That didn't save on this iPhone."
            }
            return false
        }
    }

    /// Settings › On-device › Memory: what the local assistant knows about the user. Kept on this iPhone only, used in
    /// local chats only, and never sent to a server.
    struct LocalMemoryScreen: View {
        @State private var model: LocalMemoryListModel
        @State private var draft = ""
        @State private var editing: LocalMemory?
        @State private var editText = ""
        @State private var confirmingDeleteAll = false
        @Environment(\.hermesPalette) private var palette

        init(store: any LocalMemoryStore) {
            _model = State(initialValue: LocalMemoryListModel(store: store))
        }

        var body: some View {
            List {
                Section {
                    TextField("Something to remember, like \"I'm vegetarian\"", text: $draft, axis: .vertical)
                        .accessibilityIdentifier("memory.newText")
                    Button("Remember") {
                        Task { if await model.add(draft) { draft = "" } }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("memory.add")
                    if let problem = model.problem {
                        Text(problem)
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.errorText)
                            .accessibilityIdentifier("memory.problem")
                    }
                } footer: {
                    Text(
                        "Local chats use these to answer you. They stay on this iPhone and are never sent to a server. "
                            + "Pinned ones are used first.")
                }
                Section {
                    if model.memories.isEmpty {
                        Text("Nothing saved yet.")
                            .foregroundStyle(palette.secondaryText)
                            .accessibilityIdentifier("memory.empty")
                    }
                    ForEach(model.memories) { memory in
                        row(memory)
                    }
                }
                if !model.memories.isEmpty {
                    Section {
                        Button("Delete all memories", role: .destructive) { confirmingDeleteAll = true }
                            .accessibilityIdentifier("memory.deleteAll")
                    }
                }
            }
            .navigationTitle("Memory")
            .task { await model.load() }
            .safeAreaInset(edge: .bottom, spacing: 0) { undoBar }
            .confirmationDialog(
                "Delete all memories?", isPresented: $confirmingDeleteAll, titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { Task { await model.deleteAll() } }
            } message: {
                Text("You can undo this right after.")
            }
            .alert("Edit memory", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("Memory", text: $editText)
                Button("Save") {
                    if let memory = editing { Task { _ = await model.edit(memory, to: editText) } }
                    editing = nil
                }
                Button("Cancel", role: .cancel) { editing = nil }
            }
        }

        private func row(_ memory: LocalMemory) -> some View {
            Button {
                editText = memory.text
                editing = memory
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if memory.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(palette.accent)
                            .accessibilityLabel("Pinned")
                    }
                    Text(memory.text)
                        .foregroundStyle(palette.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityIdentifier("memory.row")
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.delete(memory) } }
                    .accessibilityIdentifier("memory.delete")
            }
            .swipeActions(edge: .leading) {
                Button(memory.isPinned ? "Unpin" : "Pin", systemImage: memory.isPinned ? "pin.slash" : "pin") {
                    Task { await model.togglePin(memory) }
                }
                .tint(palette.accent)
            }
            .accessibilityAction(named: Text("Delete")) { Task { await model.delete(memory) } }
            .accessibilityAction(named: Text(memory.isPinned ? "Unpin" : "Pin")) {
                Task { await model.togglePin(memory) }
            }
        }

        @ViewBuilder
        private var undoBar: some View {
            if let change = model.lastChange {
                HStack {
                    Text(change.summary)
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    Button("Undo") { Task { await model.undo() } }
                        .accessibilityIdentifier("memory.undo")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
                .padding()
                .task(id: change) {
                    // The same 5 s window as chat delete's Undo.
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled { model.dismissUndo() }
                }
            }
        }
    }
#endif
