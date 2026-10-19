#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Share sheet: what is being shared, an optional note, and where it goes. New chat comes first, then the
    /// recent chats. The footer states what the sheet accepts.
    public struct ShareSheetView: View {
        @Bindable private var model: ShareSheetModel
        private let onCancel: () -> Void
        private let onSend: () -> Void

        public init(model: ShareSheetModel, onCancel: @escaping () -> Void, onSend: @escaping () -> Void) {
            self.model = model
            self.onCancel = onCancel
            self.onSend = onSend
        }

        public var body: some View {
            NavigationStack {
                Form {
                    if model.isUnavailable {
                        unavailableSection
                    } else {
                        previewSection
                        noticeSection
                        noteSection
                        destinationSection
                    }
                }
                .navigationTitle("Send to Hermes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                            .accessibilityIdentifier("share.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send", action: onSend)
                            .disabled(!model.canSend)
                            .accessibilityIdentifier("share.send")
                    }
                }
            }
        }

        private var previewSection: some View {
            Section("Sharing") {
                if model.items.isEmpty {
                    Text("Nothing here can be shared.")
                        .foregroundStyle(HermesColor.secondaryText)
                }
                ForEach(model.items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(2)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(HermesFont.caption)
                                    .foregroundStyle(HermesColor.secondaryText)
                            }
                        }
                    } icon: {
                        Image(systemName: item.kind.systemImage)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(item.kind.label): \(item.title)"))
                    .accessibilityValue(Text(item.detail ?? ""))
                }
            }
        }

        @ViewBuilder
        private var noticeSection: some View {
            if !model.notices.isEmpty {
                Section {
                    ForEach(model.notices, id: \.self) { notice in
                        Label(notice, systemImage: "exclamationmark.circle")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
            }
        }

        private var noteSection: some View {
            Section("Note") {
                TextField("Add a note (optional)", text: $model.note, axis: .vertical)
                    .lineLimit(1...5)
                    .accessibilityIdentifier("share.note")
            }
        }

        private var destinationSection: some View {
            Section {
                ForEach(model.destinations) { destination in
                    let isSelected = destination.id == model.selectedID
                    Button {
                        model.selectedID = destination.id
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(destination.title)
                                    .foregroundStyle(HermesColor.primaryText)
                                    .lineLimit(2)
                                if let subtitle = destination.subtitle {
                                    Text(subtitle)
                                        .font(HermesFont.caption)
                                        .foregroundStyle(HermesColor.secondaryText)
                                }
                            }
                            Spacer(minLength: 8)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(HermesColor.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("share.destination.\(destination.id)")
                }
            } header: {
                Text("Send to")
            } footer: {
                Text(ShareLimits.summary)
            }
        }

        private var unavailableSection: some View {
            Section {
                Label("Sharing is not available", systemImage: "exclamationmark.triangle")
                Text(
                    "This install of simplyHermes cannot receive shared items. Open simplyHermes and paste or attach it there."
                )
                .font(HermesFont.footnote)
                .foregroundStyle(HermesColor.secondaryText)
            }
        }
    }
#endif
