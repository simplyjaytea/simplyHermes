#if canImport(UIKit)
    import SwiftUI

    /// A short message over the content, such as a save confirmation or the reason a call failed. A tap dismisses it.
    struct JourneyNoticeBanner: View {
        let notice: JourneyNotice
        let onDismiss: () -> Void

        var body: some View {
            Button(action: onDismiss) {
                HStack(spacing: 8) {
                    Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(notice.isError ? HermesColor.statusWarning : HermesColor.statusConnected)
                    Text(notice.text)
                        .font(HermesFont.subheadline)
                        .foregroundStyle(HermesColor.primaryText)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .accessibilityLabel(notice.text)
            .accessibilityHint("Dismisses the message")
            .accessibilityIdentifier("memory.notice")
        }
    }

    extension View {
        /// Shows the model's message at the bottom while `isActive`, reads it out, and takes it away after a few
        /// seconds. Only the screen on top passes `isActive`, so a message is shown and read out once.
        func journeyNotices(model: MemoryJourneyModel, isActive: Bool) -> some View {
            modifier(JourneyNoticeModifier(model: model, isActive: isActive))
        }
    }

    /// The overlay behind ``View/journeyNotices(model:isActive:)``.
    struct JourneyNoticeModifier: ViewModifier {
        let model: MemoryJourneyModel
        let isActive: Bool

        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }

        func body(content: Content) -> some View {
            // The task below captures these two values and not `self`, which a Sendable closure cannot hold.
            let notice = isActive ? model.notice : nil
            let owner = model
            content
                .overlay(alignment: .bottom) {
                    if let notice {
                        JourneyNoticeBanner(notice: notice) { model.dismissNotice(id: notice.id) }
                            .padding(.bottom, 12)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(HermesMotion.animation(HermesMotion.snappy, reduceMotion: reduceMotion), value: notice)
                .task(id: notice?.id) {
                    guard let noticeID = notice?.id else { return }
                    await owner.expireNotice(id: noticeID)
                }
                .onChange(of: notice) { _, latest in
                    if let latest { AccessibilityNotification.Announcement(latest.text).post() }
                }
        }
    }
#endif
