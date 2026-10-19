#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The button in the chat header that opens the artifacts gallery (WP-36).
    struct ArtifactsButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label("Artifacts", systemImage: "photo.on.rectangle")
                    .font(HermesFont.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: HermesMetrics.minTapTarget - 8)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: Capsule())
            .accessibilityIdentifier("chat.artifacts")
        }
    }

    /// The images this chat generated, as a grid. Tapping one closes the sheet and jumps to the tool row that made it.
    struct ArtifactsSheet: View {
        let artifacts: [ChatArtifact]
        /// Fetches the bytes of an image the server named.
        let media: @MainActor (String) async -> Data?
        /// Scrolls the transcript to the tool row with this id.
        let onJump: (String) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(Array(artifacts.enumerated()), id: \.element.id) { index, artifact in
                            Button {
                                onJump(artifact.id)
                                dismiss()
                            } label: {
                                ArtifactThumbnail(image: artifact.image, load: media)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Artifact \(index + 1) of \(artifacts.count)"))
                            .accessibilityHint(Text("Jumps to where it was made in the chat."))
                            .accessibilityIdentifier("artifact.\(artifact.id)")
                        }
                    }
                    .padding(12)
                }
                .overlay {
                    if artifacts.isEmpty {
                        ContentUnavailableView(
                            "No artifacts yet",
                            systemImage: "photo.on.rectangle",
                            description: Text("Images this chat generates show here.")
                        )
                    }
                }
                .navigationTitle("Artifacts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    /// One image in the gallery. A placeholder shows while the bytes load, and stays when they do not come.
    private struct ArtifactThumbnail: View {
        let image: String
        let load: @MainActor (String) async -> Data?
        @State private var picture: UIImage?
        @State private var loaded = false

        var body: some View {
            ZStack {
                HermesColor.fill
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: loaded ? "photo" : "arrow.down.circle")
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: HermesMetrics.innerRadius, style: .continuous))
            .task(id: image) {
                if let data = await load(image), let decoded = UIImage(data: data) {
                    picture = decoded
                }
                loaded = true
            }
            .contextMenu {
                if let picture {
                    // Shares the image itself, so loading a thumbnail writes no file.
                    let photo = Image(uiImage: picture)
                    ShareLink(item: photo, preview: SharePreview("Artifact", image: photo)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
#endif
