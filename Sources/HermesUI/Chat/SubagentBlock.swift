#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Delegated helpers as one expandable block in the chat (plan Q29). Each row shows the goal, what the helper is
    /// doing and how long it has run, with Steer and Stop while it works.
    struct SubagentBlock: View {
        @Bindable var chat: LiveChatModel
        @State private var isExpanded = true
        @State private var steering: SubagentRow?
        @State private var steerText = ""

        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let rows = chat.subagentRows(now: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(HermesMotion.snappy) { isExpanded.toggle() }
                    } label: {
                        HStack {
                            Label(title(rows), systemImage: "person.2")
                                .font(HermesFont.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(HermesFont.caption)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subagents.header")
                    if isExpanded {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    }
                }
                .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                .padding(.vertical, 10)
                .background(
                    HermesColor.incomingBubble,
                    in: RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
                )
                .bubbleRow(.leading)
            }
            .alert("Steer helper", isPresented: Binding(get: { steering != nil }, set: { if !$0 { steering = nil } })) {
                TextField("Guidance", text: $steerText)
                Button("Send") {
                    if let steering, !steerText.trimmingCharacters(in: .whitespaces).isEmpty {
                        chat.steerSubagent(steering.id, text: steerText)
                    }
                    steerText = ""
                    steering = nil
                }
                Button("Cancel", role: .cancel) {
                    steerText = ""
                    steering = nil
                }
            } message: {
                if let steering { Text(steering.goal) }
            }
        }

        private func title(_ rows: [SubagentRow]) -> LocalizedStringKey {
            let active = rows.filter(\.isActive).count
            return active > 0 ? "\(active) helpers working" : "\(rows.count) helpers finished"
        }

        private func rowView(_ row: SubagentRow) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if row.isActive { ProgressView().controlSize(.small) }
                    Text(row.goal)
                        .font(HermesFont.footnote.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let elapsed = row.elapsed {
                        Text(SubagentPanel.clock(elapsed))
                            .font(HermesFont.caption.monospacedDigit())
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                if let detail = row.summary ?? row.activity {
                    Text(detail)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(3)
                }
                if row.canSteer || row.canStop {
                    HStack(spacing: 12) {
                        if row.canSteer {
                            Button("Steer") { steering = row }
                        }
                        if row.canStop {
                            Button("Stop", role: .destructive) { chat.stopSubagent(row.id) }
                        }
                    }
                    .font(HermesFont.caption.weight(.semibold))
                }
            }
            .padding(.leading, CGFloat(row.depth) * 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("subagent.\(row.id)")
        }
    }
#endif
