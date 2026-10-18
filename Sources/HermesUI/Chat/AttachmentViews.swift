#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    /// Photo helpers for attachments. Photos are scaled down before they are sent, so a full-size camera image does not
    /// travel as a huge base64 payload.
    enum AttachmentImage {
        /// Longest side of a photo that is sent to Hermes.
        static let maxSide: CGFloat = 2048

        /// JPEG data of the image, scaled so its longest side is at most ``maxSide``. Nil for an empty image.
        static func jpeg(from image: UIImage) -> Data? {
            let size = image.size
            guard size.width > 0, size.height > 0 else { return nil }
            let scale = min(1, maxSide / max(size.width, size.height))
            let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: target, format: format)
            return renderer.jpegData(withCompressionQuality: 0.8) { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }
    }

    /// The files waiting in the composer, above its text. Photos show as thumbnails, other files as a name chip.
    struct AttachmentStrip: View {
        @Binding var attachments: [ComposerAttachment]

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { file in
                        AttachmentTile(file: file) {
                            attachments.removeAll { $0.id == file.id }
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            .accessibilityIdentifier("composer.attachments")
        }
    }

    /// One attached file. The button in its corner removes it before it is sent.
    private struct AttachmentTile: View {
        let file: ComposerAttachment
        let onRemove: () -> Void

        var body: some View {
            Group {
                if file.kind == .image, let image = UIImage(data: file.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: file.kind == .pdf ? "doc.richtext" : "doc")
                            .foregroundStyle(HermesColor.secondaryText)
                        Text(file.name)
                            .font(HermesFont.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 56)
                    .frame(maxWidth: 180)
                    .background(HermesColor.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.6))
                        .frame(width: HermesMetrics.minTapTarget / 2, height: HermesMetrics.minTapTarget / 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(file.name)"))
                .offset(x: 8, y: -8)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("composer.attachment.\(file.name)")
        }
    }

    /// The system camera, as a sheet. It hands back the photo it took and closes.
    struct CameraPicker: UIViewControllerRepresentable {
        let onCapture: (UIImage) -> Void
        @Environment(\.dismiss) private var dismiss

        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onCapture: onCapture, dismiss: dismiss)
        }

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

        @MainActor
        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            private let onCapture: (UIImage) -> Void
            private let dismiss: DismissAction

            init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
                self.onCapture = onCapture
                self.dismiss = dismiss
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let image = info[.originalImage] as? UIImage { onCapture(image) }
                dismiss()
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                dismiss()
            }
        }
    }
#endif
