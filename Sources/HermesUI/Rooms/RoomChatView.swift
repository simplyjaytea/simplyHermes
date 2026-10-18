#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// One group chat: its transcript, the room's line and approvals, the composer, and Stop (WP-43; plan Q35).
    struct RoomChatView: View {
        @Bindable var model: RoomChatModel
        @Environment(\.dismiss) private var dismiss
        @State private var isSettingsPresented = false
        @State private var isConfirmingRetry = false
        @State private var retryAction: RoomPendingAction?

        var body: some View {
            VStack(spacing: 0) {
                transcript
                statusArea
                if let note = model.readOnlyNote {
                    readOnlyNote(note)
                } else {
                    composerArea
                }
            }
            .navigationTitle(model.room.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if RoomStatus.showsStop(model.status) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Stop", systemImage: "stop.fill", role: .destructive) {
                            Task { await model.stop() }
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Group Settings", systemImage: "slider.horizontal.3") {
                        isSettingsPresented = true
                    }
                }
            }
            .task { await model.run() }
            .sheet(isPresented: $isSettingsPresented) {
                RoomSettingsSheet(model: model)
            }
            .confirmationDialog("Run this turn again?", isPresented: $isConfirmingRetry, titleVisibility: .visible) {
                Button("Run Again") {
                    guard let action = retryAction else { return }
                    Task { await model.retry(action) }
                }
            } message: {
                Text("The room may already have run part of this turn.")
            }
            .onChange(of: model.isDisbanded) { _, disbanded in
                if disbanded { dismiss() }
            }
        }

        private var transcript: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.rows) { row in
                            RoomRowView(row: row, chat: model)
                                .id(row.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: model.rows.last?.id) { _, last in
                    guard let last else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView(
                        "No messages yet", systemImage: "person.3",
                        description: Text("Say something to start the group."))
                }
            }
        }

        /// The line the driver shows, or the approval it waits on, then any retry offer and the last failure.
        private var statusArea: some View {
            VStack(alignment: .leading, spacing: 6) {
                if let action = RoomStatus.pendingApproval(in: model.status) {
                    approvalArea(action)
                } else if let line = RoomStatus.line(for: model.status) {
                    Text(line)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                if let retry = RoomStatus.pendingActions(in: model.status).first(where: { $0.kind == "retry" }) {
                    Button("Run This Turn Again…") {
                        retryAction = retry
                        isConfirmingRetry = true
                    }
                    .font(HermesFont.footnote)
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.destructive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }

        /// The approval shows the command it would run, so the user answers knowing what it is.
        private func approvalArea(_ action: RoomPendingAction) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Waiting for your answer…")
                    .font(HermesFont.footnote.weight(.semibold))
                if let command = action.approval?.command {
                    Text(command)
                        .font(HermesFont.codeSmall)
                        .textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    Button("Allow Once") {
                        Task { await model.answer(action, with: .once) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Deny", role: .destructive) {
                        Task { await model.answer(action, with: .deny) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private var composerArea: some View {
            VStack(alignment: .leading, spacing: 8) {
                if let completion = model.completion {
                    let options = RoomMentions.options(for: completion, handles: model.handles)
                    if !options.isEmpty {
                        mentionPicker(options, completion: completion)
                    }
                }
                if RoomMentions.isSlashCommand(model.draft.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Text(RoomError.slashCommand.message)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.destructive)
                }
                Composer(
                    text: $model.draft, placeholder: "Message the group",
                    onSend: {
                        Task { await model.send() }
                    })
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }

        private func mentionPicker(_ options: [String], completion: RoomCompletion) -> some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { handle in
                        Button("@\(handle)") {
                            model.draft = RoomMentions.inserting(handle, into: model.draft, replacing: completion)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }

        private func readOnlyNote(_ note: String) -> some View {
            Text(note)
                .font(HermesFont.footnote)
                .foregroundStyle(HermesColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .background(HermesColor.groupedBackground)
        }
    }
#endif
