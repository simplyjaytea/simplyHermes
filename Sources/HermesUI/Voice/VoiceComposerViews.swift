#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The microphone at the end of the composer. A tap dictates. The menu starts a voice conversation and turns
    /// read-aloud on or off.
    struct VoiceMicButton: View {
        let voice: VoiceInputModel
        @AppStorage(VoicePreferences.readAloudKey) private var readAloud = false

        var body: some View {
            Button {
                voice.startDictation()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HermesColor.primaryText)
                    .frame(width: 32, height: 32)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dictate"))
            .accessibilityIdentifier("composer.voice")
            .contextMenu {
                Button("Voice conversation", systemImage: "waveform") { voice.startConversation() }
                Toggle("Read replies aloud", systemImage: "speaker.wave.2", isOn: $readAloud)
            }
        }
    }

    /// What replaces the field while voice is on: a cancel button, the waveform with its status, and a finish button.
    struct VoiceWaveBar: View {
        let voice: VoiceInputModel

        var body: some View {
            HStack(spacing: 10) {
                Button {
                    voice.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HermesColor.secondaryText)
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Cancel"))

                VStack(alignment: .leading, spacing: 2) {
                    WaveformBars(levels: voice.levels)
                    Text(voice.problem ?? voice.statusText)
                        .font(.caption)
                        .foregroundStyle(voice.problem == nil ? HermesColor.secondaryText : HermesColor.destructive)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(voice.problem ?? voice.statusText))
                .accessibilityIdentifier("composer.voiceStatus")

                Button {
                    voice.finish()
                } label: {
                    Image(systemName: voice.mode == .conversation ? "stop.fill" : "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(HermesColor.onAccent)
                        .frame(width: 32, height: 32)
                        .background(HermesColor.accent, in: Circle())
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(voice.mode == .conversation ? "End voice conversation" : "Insert dictation"))
            }
            .padding(.vertical, 2)
        }
    }

    /// A voice problem under the composer while voice is off, so a failed dictation is not silent. The next start
    /// clears it.
    struct VoiceProblemLine: View {
        let problem: String

        var body: some View {
            Text(problem)
                .font(.caption)
                .foregroundStyle(HermesColor.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
    }

    /// Bars of recent loudness. Decorative: the status line carries the meaning for VoiceOver.
    struct WaveformBars: View {
        let levels: [Double]
        private let slots = 48

        var body: some View {
            Canvas { context, size in
                let spacing: CGFloat = 3
                let width = max(2, (size.width - spacing * CGFloat(slots - 1)) / CGFloat(slots))
                let recent = levels.suffix(slots)
                let first = slots - recent.count
                for (index, level) in recent.enumerated() {
                    let height = max(3, CGFloat(level) * size.height)
                    let rect = CGRect(
                        x: CGFloat(first + index) * (width + spacing),
                        y: (size.height - height) / 2,
                        width: width,
                        height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(HermesColor.accent))
                }
            }
            .frame(height: 28)
            .accessibilityHidden(true)
        }
    }
#endif
